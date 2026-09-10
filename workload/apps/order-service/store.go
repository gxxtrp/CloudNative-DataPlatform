package main

import (
	"context"
	"crypto/tls"
	"database/sql"
	_ "embed"
	"encoding/json"
	"fmt"
	"os"
	"strconv"
	"time"

	"cloud.google.com/go/cloudsqlconn"
	"cloud.google.com/go/cloudsqlconn/postgres/pgxv5"
	"github.com/segmentio/kafka-go"
	"github.com/segmentio/kafka-go/sasl/plain"
	"golang.org/x/oauth2/google"
)

//go:embed schema.sql
var orderSchema string

type OrderStore interface {
	Create(context.Context, Order, OutboxEvent) error
	UpdateStatus(context.Context, string, string, OutboxEvent) (Order, error)
	Pending(context.Context, int) ([]OutboxEvent, error)
	MarkPublished(context.Context, int64) error
	PendingCount(context.Context) (int, error)
	Close() error
}

type postgresOrderStore struct {
	db      *sql.DB
	cleanup func() error
}

func newPostgresOrderStore(ctx context.Context) (*postgresOrderStore, error) {
	instance, database, user := requiredEnv("CLOUD_SQL_INSTANCE"), requiredEnv("DATABASE_NAME"), requiredEnv("DATABASE_USER")
	cleanup, err := pgxv5.RegisterDriver("order-cloudsql", cloudsqlconn.WithIAMAuthN(), cloudsqlconn.WithDefaultDialOptions(cloudsqlconn.WithPrivateIP()))
	if err != nil {
		return nil, fmt.Errorf("register Cloud SQL driver: %w", err)
	}
	db, err := sql.Open("order-cloudsql", fmt.Sprintf("host=%s user=%s dbname=%s sslmode=disable search_path=order_service", instance, user, database))
	if err != nil {
		_ = cleanup()
		return nil, fmt.Errorf("open Cloud SQL: %w", err)
	}
	db.SetMaxOpenConns(5)
	db.SetMaxIdleConns(2)
	db.SetConnMaxLifetime(30 * time.Minute)
	s := &postgresOrderStore{db: db, cleanup: cleanup}
	if _, err := db.ExecContext(ctx, orderSchema); err != nil {
		_ = s.Close()
		return nil, fmt.Errorf("apply order schema: %w", err)
	}
	if err := db.PingContext(ctx); err != nil {
		_ = s.Close()
		return nil, fmt.Errorf("ping Cloud SQL: %w", err)
	}
	return s, nil
}

func (s *postgresOrderStore) Create(ctx context.Context, order Order, event OutboxEvent) error {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback() }()
	items, err := json.Marshal(order.Items)
	if err != nil {
		return err
	}
	if _, err = tx.ExecContext(ctx, `INSERT INTO orders (id, customer_id, merchant_id, amount, currency, payment_method, status, items, delivery_address) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)`, order.OrderID, order.CustomerID, order.MerchantID, order.Amount, order.Currency, order.PaymentMethod, order.Status, items, order.DeliveryAddress); err != nil {
		return fmt.Errorf("insert order: %w", err)
	}
	if err = insertOrderOutbox(ctx, tx, event); err != nil {
		return err
	}
	return tx.Commit()
}

func (s *postgresOrderStore) UpdateStatus(ctx context.Context, id, status string, event OutboxEvent) (Order, error) {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return Order{}, err
	}
	defer func() { _ = tx.Rollback() }()
	row := tx.QueryRowContext(ctx, `UPDATE orders SET status=$2, updated_at=NOW() WHERE id=$1 RETURNING id,customer_id,merchant_id,amount,currency,payment_method,status,items,delivery_address,created_at,updated_at`, id, status)
	order, err := scanOrder(row)
	if err != nil {
		return Order{}, err
	}
	event.Payload, err = json.Marshal(newOrderLifecycleEvent(order, event.EventID))
	if err != nil {
		return Order{}, err
	}
	if err = insertOrderOutbox(ctx, tx, event); err != nil {
		return Order{}, err
	}
	if err = tx.Commit(); err != nil {
		return Order{}, err
	}
	return order, nil
}

func insertOrderOutbox(ctx context.Context, tx *sql.Tx, event OutboxEvent) error {
	_, err := tx.ExecContext(ctx, `INSERT INTO order_outbox (event_id,aggregate_id,event_type,payload,status) VALUES ($1,$2,$3,$4,'PENDING')`, event.EventID, event.AggregateID, event.EventType, event.Payload)
	if err != nil {
		return fmt.Errorf("insert order outbox: %w", err)
	}
	return nil
}

func (s *postgresOrderStore) Pending(ctx context.Context, limit int) ([]OutboxEvent, error) {
	rows, err := s.db.QueryContext(ctx, `SELECT id,event_id,aggregate_id,event_type,payload,status,created_at FROM order_outbox WHERE status='PENDING' ORDER BY id LIMIT $1`, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var events []OutboxEvent
	for rows.Next() {
		var event OutboxEvent
		if err := rows.Scan(&event.ID, &event.EventID, &event.AggregateID, &event.EventType, &event.Payload, &event.Status, &event.CreatedAt); err != nil {
			return nil, err
		}
		events = append(events, event)
	}
	return events, rows.Err()
}

func (s *postgresOrderStore) MarkPublished(ctx context.Context, id int64) error {
	_, err := s.db.ExecContext(ctx, `UPDATE order_outbox SET status='PUBLISHED',published_at=NOW() WHERE id=$1 AND status='PENDING'`, id)
	return err
}
func (s *postgresOrderStore) PendingCount(ctx context.Context) (int, error) {
	var n int
	err := s.db.QueryRowContext(ctx, `SELECT COUNT(*) FROM order_outbox WHERE status='PENDING'`).Scan(&n)
	return n, err
}
func (s *postgresOrderStore) Close() error {
	err := s.db.Close()
	cleanupErr := s.cleanup()
	if err != nil {
		return err
	}
	return cleanupErr
}

type orderScanner interface{ Scan(...any) error }

func scanOrder(row orderScanner) (Order, error) {
	var order Order
	var amount string
	var items []byte
	var created, updated time.Time
	if err := row.Scan(&order.OrderID, &order.CustomerID, &order.MerchantID, &amount, &order.Currency, &order.PaymentMethod, &order.Status, &items, &order.DeliveryAddress, &created, &updated); err != nil {
		return Order{}, err
	}
	parsed, err := strconv.ParseFloat(amount, 64)
	if err != nil {
		return Order{}, err
	}
	order.Amount = parsed
	if len(items) > 0 {
		if err := json.Unmarshal(items, &order.Items); err != nil {
			return Order{}, err
		}
	}
	order.CreatedAt = created.UTC().Format(time.RFC3339)
	order.UpdatedAt = updated.UTC().Format(time.RFC3339)
	return order, nil
}

type kafkaOrderPublisher struct{ bootstrap, topic, client string }

func newKafkaOrderPublisher() *kafkaOrderPublisher {
	return &kafkaOrderPublisher{requiredEnv("KAFKA_BOOTSTRAP_SERVERS"), requiredEnv("KAFKA_TOPIC"), requiredEnv("KAFKA_CLIENT_EMAIL")}
}
func (p *kafkaOrderPublisher) Publish(ctx context.Context, event OutboxEvent) error {
	tokens, err := google.DefaultTokenSource(ctx, "https://www.googleapis.com/auth/cloud-platform")
	if err != nil {
		return err
	}
	token, err := tokens.Token()
	if err != nil {
		return err
	}
	writer := &kafka.Writer{Addr: kafka.TCP(p.bootstrap), Topic: p.topic, Balancer: &kafka.Hash{}, RequiredAcks: kafka.RequireAll, MaxAttempts: 3, Transport: &kafka.Transport{TLS: &tls.Config{MinVersion: tls.VersionTLS12}, SASL: plain.Mechanism{Username: p.client, Password: token.AccessToken}}}
	defer writer.Close()
	return writer.WriteMessages(ctx, kafka.Message{Key: []byte(event.AggregateID), Value: event.Payload, Headers: []kafka.Header{{Key: "event_id", Value: []byte(event.EventID)}, {Key: "event_type", Value: []byte(event.EventType)}}})
}

func requiredEnv(name string) string {
	if value := os.Getenv(name); value != "" {
		return value
	}
	panic(fmt.Sprintf("%s is required", name))
}
