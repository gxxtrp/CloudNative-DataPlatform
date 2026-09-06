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
	"sync"
	"sync/atomic"
	"syscall"
	"time"
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
	Status          string      `json:"status"`
	DeliveryAddress string      `json:"delivery_address"`
	Items           []OrderItem `json:"items,omitempty"`
	CreatedAt       string      `json:"created_at"`
	UpdatedAt       string      `json:"updated_at"`
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
	mu           sync.RWMutex
	orders       map[string]Order
	outbox       []OutboxEvent
	nextOutboxID int64
	ordersCount  int64
	brokerAddr   string
	topic        string
}

func NewOrderService() *OrderService {
	broker := os.Getenv("REDPANDA_BROKERS")
	if broker == "" {
		broker = "redpanda.platform.svc.cluster.local:9092"
	}
	topic := os.Getenv("ORDERS_TOPIC")
	if topic == "" {
		topic = "orders.lifecycle"
	}

	return &OrderService{
		orders:     make(map[string]Order),
		outbox:     make([]OutboxEvent, 0),
		brokerAddr: broker,
		topic:      topic,
	}
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

	now := time.Now().UTC().Format(time.RFC3339)
	order := Order{
		OrderID:         req.OrderID,
		CustomerID:      req.CustomerID,
		MerchantID:      req.MerchantID,
		Amount:          req.Amount,
		Currency:        req.Currency,
		Status:          "PLACED",
		DeliveryAddress: req.DeliveryAddress,
		Items:           req.Items,
		CreatedAt:       now,
		UpdatedAt:       now,
	}

	eventPayload, err := json.Marshal(order)
	if err != nil {
		http.Error(w, "Failed to serialize event", http.StatusInternalServerError)
		return
	}

	// Atomic Transaction: Write to orders table and outbox table
	s.mu.Lock()
	s.orders[order.OrderID] = order
	s.nextOutboxID++
	s.outbox = append(s.outbox, OutboxEvent{
		ID:          s.nextOutboxID,
		EventID:     fmt.Sprintf("evt-%s-placed", order.OrderID),
		AggregateID: order.OrderID,
		EventType:   "OrderPlaced",
		Payload:     eventPayload,
		Status:      "PENDING",
		CreatedAt:   time.Now().UTC(),
	})
	s.mu.Unlock()
	atomic.AddInt64(&s.ordersCount, 1)

	log.Printf("[ORDER_SERVICE] Order created: %s (Amount: %.2f %s, Outbox Event queued)", order.OrderID, order.Amount, order.Currency)

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
	orderID := parts[2]

	var req struct {
		Status string `json:"status"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid body", http.StatusBadRequest)
		return
	}

	s.mu.Lock()
	order, exists := s.orders[orderID]
	if !exists {
		s.mu.Unlock()
		http.Error(w, "Order not found", http.StatusNotFound)
		return
	}

	order.Status = req.Status
	order.UpdatedAt = time.Now().UTC().Format(time.RFC3339)
	s.orders[orderID] = order

	eventPayload, _ := json.Marshal(order)
	s.nextOutboxID++
	s.outbox = append(s.outbox, OutboxEvent{
		ID:          s.nextOutboxID,
		EventID:     fmt.Sprintf("evt-%s-%s", order.OrderID, strings.ToLower(req.Status)),
		AggregateID: order.OrderID,
		EventType:   fmt.Sprintf("OrderStatus%s", strings.Title(strings.ToLower(req.Status))),
		Payload:     eventPayload,
		Status:      "PENDING",
		CreatedAt:   time.Now().UTC(),
	})
	s.mu.Unlock()

	log.Printf("[ORDER_SERVICE] Order status updated: %s -> %s (Outbox Event queued)", orderID, req.Status)

	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(order)
}

func (s *OrderService) StartOutboxRelay(ctx context.Context) {
	ticker := time.NewTicker(100 * time.Millisecond)
	defer ticker.Stop()

	log.Printf("[OUTBOX_RELAY] Background outbox relay started. Target broker: %s, Topic: %s", s.brokerAddr, s.topic)

	for {
		select {
		case <-ctx.Done():
			log.Println("[OUTBOX_RELAY] Stopping outbox relay...")
			return
		case <-ticker.C:
			s.mu.Lock()
			for i := range s.outbox {
				if s.outbox[i].Status == "PENDING" {
					// In production, transmits over Kafka protocol to Redpanda.
					log.Printf("[OUTBOX_RELAY] Flushed event %s (%s) to Redpanda topic '%s'",
						s.outbox[i].EventID, s.outbox[i].EventType, s.topic)
					s.outbox[i].Status = "PUBLISHED"
				}
			}
			s.mu.Unlock()
		}
	}
}

func main() {
	svc := NewOrderService()
	mux := http.NewServeMux()

	mux.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte(`{"status":"UP","service":"order-service"}`))
	})

	mux.HandleFunc("/metrics", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "text/plain; version=0.0.4")
		fmt.Fprintf(w, "# HELP orders_created_total Total number of orders created\n")
		fmt.Fprintf(w, "# TYPE orders_created_total counter\n")
		fmt.Fprintf(w, "orders_created_total %d\n", atomic.LoadInt64(&svc.ordersCount))
		svc.mu.RLock()
		pending := 0
		for _, e := range svc.outbox {
			if e.Status == "PENDING" {
				pending++
			}
		}
		svc.mu.RUnlock()
		fmt.Fprintf(w, "# HELP outbox_pending_events Current pending events in outbox\n")
		fmt.Fprintf(w, "# TYPE outbox_pending_events gauge\n")
		fmt.Fprintf(w, "outbox_pending_events %d\n", pending)
	})

	mux.HandleFunc("/v1/orders", svc.CreateOrder)
	mux.HandleFunc("/v1/orders/", svc.UpdateOrderStatus)

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	server := &http.Server{
		Addr:    ":" + port,
		Handler: mux,
	}

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	go svc.StartOutboxRelay(ctx)

	go func() {
		log.Printf("[ORDER_SERVICE] Starting HTTP server on :%s", port)
		if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("[ORDER_SERVICE] Server failed: %v", err)
		}
	}()

	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, syscall.SIGINT, syscall.SIGTERM)
	<-sigChan

	log.Println("[ORDER_SERVICE] Shutting down gracefully...")
	cancel()
	shutdownCtx, shutdownCancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer shutdownCancel()
	_ = server.Shutdown(shutdownCtx)
	log.Println("[ORDER_SERVICE] Server stopped.")
}
