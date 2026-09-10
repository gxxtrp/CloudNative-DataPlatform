package main

import (
	"context"
	"crypto/tls"
	"database/sql"
	_ "embed"
	"fmt"
	"os"
	"time"

	"cloud.google.com/go/cloudsqlconn"
	"cloud.google.com/go/cloudsqlconn/postgres/pgxv5"
	"github.com/segmentio/kafka-go"
	"github.com/segmentio/kafka-go/sasl/plain"
	"golang.org/x/oauth2/google"
)

//go:embed schema.sql
var riderSchema string

type RiderStore interface {
	RecordTelemetry(context.Context, RiderTelemetry, OutboxEvent) error
	Pending(context.Context, int) ([]OutboxEvent, error)
	MarkPublished(context.Context, int64) error
	PendingCount(context.Context) (int, error)
	Close() error
}

type postgresRiderStore struct {
	db      *sql.DB
	cleanup func() error
}

func newPostgresRiderStore(ctx context.Context) (*postgresRiderStore, error) {
	instance, database, user := requiredEnv("CLOUD_SQL_INSTANCE"), requiredEnv("DATABASE_NAME"), requiredEnv("DATABASE_USER")
	cleanup, err := pgxv5.RegisterDriver("rider-cloudsql", cloudsqlconn.WithIAMAuthN(), cloudsqlconn.WithDefaultDialOptions(cloudsqlconn.WithPrivateIP()))
	if err != nil {
		return nil, fmt.Errorf("register Cloud SQL driver: %w", err)
	}
	db, err := sql.Open("rider-cloudsql", fmt.Sprintf("host=%s user=%s dbname=%s sslmode=disable search_path=rider_service", instance, user, database))
	if err != nil {
		_ = cleanup()
		return nil, err
	}
	db.SetMaxOpenConns(5)
	db.SetMaxIdleConns(2)
	db.SetConnMaxLifetime(30 * time.Minute)
	s := &postgresRiderStore{db: db, cleanup: cleanup}
	if _, err := db.ExecContext(ctx, riderSchema); err != nil {
		_ = s.Close()
		return nil, fmt.Errorf("apply rider schema: %w", err)
	}
	if err := db.PingContext(ctx); err != nil {
		_ = s.Close()
		return nil, fmt.Errorf("ping Cloud SQL: %w", err)
	}
	return s, nil
}

func (s *postgresRiderStore) RecordTelemetry(ctx context.Context, telemetry RiderTelemetry, event OutboxEvent) error {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback() }()
	if _, err = tx.ExecContext(ctx, `INSERT INTO riders (id,name,status,last_latitude,last_longitude,last_ping_at) VALUES ($1,$1,$2,$3,$4,NOW()) ON CONFLICT (id) DO UPDATE SET status=EXCLUDED.status,last_latitude=EXCLUDED.last_latitude,last_longitude=EXCLUDED.last_longitude,last_ping_at=EXCLUDED.last_ping_at`, telemetry.RiderID, telemetry.Status, telemetry.Latitude, telemetry.Longitude); err != nil {
		return fmt.Errorf("upsert rider: %w", err)
	}
	if err = insertRiderOutbox(ctx, tx, event); err != nil {
		return err
	}
	return tx.Commit()
}
func insertRiderOutbox(ctx context.Context, tx *sql.Tx, event OutboxEvent) error {
	_, err := tx.ExecContext(ctx, `INSERT INTO rider_outbox (event_id,aggregate_id,event_type,payload,status) VALUES ($1,$2,$3,$4,'PENDING')`, event.EventID, event.AggregateID, event.EventType, event.Payload)
	if err != nil {
		return fmt.Errorf("insert rider outbox: %w", err)
	}
	return nil
}
func (s *postgresRiderStore) Pending(ctx context.Context, limit int) ([]OutboxEvent, error) {
	rows, err := s.db.QueryContext(ctx, `SELECT id,event_id,aggregate_id,event_type,payload,status,created_at FROM rider_outbox WHERE status='PENDING' ORDER BY id LIMIT $1`, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var events []OutboxEvent
	for rows.Next() {
		var e OutboxEvent
		if err := rows.Scan(&e.ID, &e.EventID, &e.AggregateID, &e.EventType, &e.Payload, &e.Status, &e.CreatedAt); err != nil {
			return nil, err
		}
		events = append(events, e)
	}
	return events, rows.Err()
}
func (s *postgresRiderStore) MarkPublished(ctx context.Context, id int64) error {
	_, err := s.db.ExecContext(ctx, `UPDATE rider_outbox SET status='PUBLISHED',published_at=NOW() WHERE id=$1 AND status='PENDING'`, id)
	return err
}
func (s *postgresRiderStore) PendingCount(ctx context.Context) (int, error) {
	var n int
	err := s.db.QueryRowContext(ctx, `SELECT COUNT(*) FROM rider_outbox WHERE status='PENDING'`).Scan(&n)
	return n, err
}
func (s *postgresRiderStore) Close() error {
	err := s.db.Close()
	cleanupErr := s.cleanup()
	if err != nil {
		return err
	}
	return cleanupErr
}

type kafkaRiderPublisher struct{ bootstrap, topic, client string }

func newKafkaRiderPublisher() *kafkaRiderPublisher {
	return &kafkaRiderPublisher{requiredEnv("KAFKA_BOOTSTRAP_SERVERS"), requiredEnv("KAFKA_TOPIC"), requiredEnv("KAFKA_CLIENT_EMAIL")}
}
func (p *kafkaRiderPublisher) Publish(ctx context.Context, event OutboxEvent) error {
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
