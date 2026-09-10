package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"strings"
	"sync/atomic"
	"syscall"
	"time"

	"github.com/google/uuid"
)

type OrderItem struct {
	ItemID   string  `json:"item_id"`
	Name     string  `json:"name"`
	Price    float64 `json:"price"`
	Quantity int     `json:"quantity"`
}
type Order struct {
	OrderID         string      `json:"order_id"`
	CustomerID      string      `json:"customer_id"`
	MerchantID      string      `json:"merchant_id"`
	Amount          float64     `json:"amount"`
	Currency        string      `json:"currency"`
	PaymentMethod   string      `json:"payment_method"`
	Status          string      `json:"status"`
	DeliveryAddress string      `json:"delivery_address"`
	Items           []OrderItem `json:"items,omitempty"`
	CreatedAt       string      `json:"created_at"`
	UpdatedAt       string      `json:"updated_at"`
}

type orderLifecycleEvent struct {
	EventID         string               `json:"event_id"`
	EventTimestamp  string               `json:"event_timestamp"`
	SchemaVersion   string               `json:"schema_version"`
	Producer        string               `json:"producer"`
	OrderID         string               `json:"order_id"`
	OrderStatus     string               `json:"order_status"`
	MerchantID      string               `json:"merchant_id"`
	CustomerID      string               `json:"customer_id"`
	TotalAmountBaht float64              `json:"total_amount_baht"`
	PaymentMethod   string               `json:"payment_method"`
	Items           []orderLifecycleItem `json:"items,omitempty"`
}

type orderLifecycleItem struct {
	ItemID    string  `json:"item_id"`
	ItemName  string  `json:"item_name"`
	Quantity  int     `json:"quantity"`
	PriceBaht float64 `json:"price_baht"`
}
type OutboxEvent struct {
	ID          int64           `json:"id"`
	EventID     string          `json:"event_id"`
	AggregateID string          `json:"aggregate_id"`
	EventType   string          `json:"event_type"`
	Payload     json.RawMessage `json:"payload"`
	Status      string          `json:"status"`
	CreatedAt   time.Time       `json:"created_at"`
}

type OrderService struct {
	store       OrderStore
	publisher   *kafkaOrderPublisher
	ordersCount int64
}

func newOrderService(store OrderStore, publisher *kafkaOrderPublisher) *OrderService {
	return &OrderService{store: store, publisher: publisher}
}

func (s *OrderService) CreateOrder(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}
	var req struct {
		OrderID         string      `json:"order_id"`
		CustomerID      string      `json:"customer_id"`
		MerchantID      string      `json:"merchant_id"`
		Amount          float64     `json:"amount"`
		Currency        string      `json:"currency"`
		PaymentMethod   string      `json:"payment_method"`
		DeliveryAddress string      `json:"delivery_address"`
		Items           []OrderItem `json:"items"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, fmt.Sprintf("Invalid JSON: %v", err), http.StatusBadRequest)
		return
	}
	if req.OrderID == "" || req.CustomerID == "" || req.MerchantID == "" || req.Amount < 0 {
		http.Error(w, "Validation failed: order_id, customer_id, merchant_id required and amount >= 0", http.StatusUnprocessableEntity)
		return
	}
	if req.Currency == "" {
		req.Currency = "THB"
	}
	if req.Currency != "THB" {
		http.Error(w, "Only THB orders are supported by the v2 contract", http.StatusUnprocessableEntity)
		return
	}
	if req.PaymentMethod == "" {
		req.PaymentMethod = "CASH_ON_DELIVERY"
	}
	if !isValidPaymentMethod(req.PaymentMethod) {
		http.Error(w, "Unsupported payment_method", http.StatusUnprocessableEntity)
		return
	}
	now := time.Now().UTC().Format(time.RFC3339)
	order := Order{OrderID: req.OrderID, CustomerID: req.CustomerID, MerchantID: req.MerchantID, Amount: req.Amount, Currency: req.Currency, PaymentMethod: req.PaymentMethod, Status: "CREATED", DeliveryAddress: req.DeliveryAddress, Items: req.Items, CreatedAt: now, UpdatedAt: now}
	eventID := uuid.NewString()
	payload, err := json.Marshal(newOrderLifecycleEvent(order, eventID))
	if err != nil {
		http.Error(w, "Failed to serialize event", http.StatusInternalServerError)
		return
	}
	event := OutboxEvent{EventID: eventID, AggregateID: order.OrderID, EventType: "OrderCreated", Payload: payload}
	if err := s.store.Create(r.Context(), order, event); err != nil {
		http.Error(w, "Could not persist order", http.StatusConflict)
		return
	}
	atomic.AddInt64(&s.ordersCount, 1)
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusCreated)
	_ = json.NewEncoder(w).Encode(order)
}

func (s *OrderService) UpdateOrderStatus(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost && r.Method != http.MethodPut {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}
	parts := strings.Split(strings.Trim(r.URL.Path, "/"), "/")
	if len(parts) < 4 || parts[0] != "v1" || parts[1] != "orders" || parts[3] != "status" {
		http.Error(w, "Path must be /v1/orders/{id}/status", http.StatusBadRequest)
		return
	}
	var req struct {
		Status string `json:"status"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || !isValidOrderStatus(req.Status) {
		http.Error(w, "Valid status is required", http.StatusBadRequest)
		return
	}
	event := OutboxEvent{EventID: uuid.NewString(), AggregateID: parts[2], EventType: "OrderStatusChanged"}
	order, err := s.store.UpdateStatus(r.Context(), parts[2], req.Status, event)
	if err != nil {
		http.Error(w, "Order not found", http.StatusNotFound)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(order)
}

func newOrderLifecycleEvent(order Order, eventID string) orderLifecycleEvent {
	items := make([]orderLifecycleItem, 0, len(order.Items))
	for _, item := range order.Items {
		items = append(items, orderLifecycleItem{ItemID: item.ItemID, ItemName: item.Name, Quantity: item.Quantity, PriceBaht: item.Price})
	}
	return orderLifecycleEvent{
		EventID: eventID, EventTimestamp: order.UpdatedAt, SchemaVersion: "2.0.0", Producer: "order-service",
		OrderID: order.OrderID, OrderStatus: order.Status, MerchantID: order.MerchantID, CustomerID: order.CustomerID,
		TotalAmountBaht: order.Amount, PaymentMethod: order.PaymentMethod, Items: items,
	}
}

func isValidOrderStatus(status string) bool {
	return map[string]bool{"CREATED": true, "MERCHANT_ACCEPTED": true, "RIDER_ASSIGNED": true, "PICKED_UP": true, "DELIVERED": true, "CANCELLED": true}[status]
}

func isValidPaymentMethod(method string) bool {
	return map[string]bool{"LINE_PAY": true, "PROMPTPAY": true, "CREDIT_CARD": true, "CASH_ON_DELIVERY": true}[method]
}

func (s *OrderService) StartOutboxRelay(ctx context.Context) {
	ticker := time.NewTicker(time.Second)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			events, err := s.store.Pending(ctx, 50)
			if err != nil {
				log.Printf("[OUTBOX_RELAY] read: %v", err)
				continue
			}
			for _, event := range events {
				if err := s.publisher.Publish(ctx, event); err != nil {
					log.Printf("[OUTBOX_RELAY] publish %s: %v", event.EventID, err)
					continue
				}
				if err := s.store.MarkPublished(ctx, event.ID); err != nil {
					log.Printf("[OUTBOX_RELAY] mark %s: %v", event.EventID, err)
				}
			}
		}
	}
}

func main() {
	ctx, cancel := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer cancel()
	store, err := newPostgresOrderStore(ctx)
	if err != nil {
		log.Fatalf("[ORDER_SERVICE] durable store: %v", err)
	}
	defer store.Close()
	svc := newOrderService(store, newKafkaOrderPublisher())
	mux := http.NewServeMux()
	mux.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte(`{"status":"UP","service":"order-service"}`))
	})
	mux.HandleFunc("/metrics", func(w http.ResponseWriter, r *http.Request) {
		pending, _ := store.PendingCount(r.Context())
		w.Header().Set("Content-Type", "text/plain; version=0.0.4")
		fmt.Fprintf(w, "orders_created_total %d\noutbox_pending_events %d\n", atomic.LoadInt64(&svc.ordersCount), pending)
	})
	mux.HandleFunc("/v1/orders", svc.CreateOrder)
	mux.HandleFunc("/v1/orders/", svc.UpdateOrderStatus)
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}
	server := &http.Server{Addr: ":" + port, Handler: mux, ReadHeaderTimeout: 5 * time.Second}
	go svc.StartOutboxRelay(ctx)
	go func() {
		if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("[ORDER_SERVICE] server: %v", err)
		}
	}()
	<-ctx.Done()
	shutdownCtx, shutdownCancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer shutdownCancel()
	_ = server.Shutdown(shutdownCtx)
}
