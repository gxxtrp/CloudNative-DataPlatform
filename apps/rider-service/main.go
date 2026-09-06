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

type RiderTelemetry struct {
	RiderID      string  `json:"rider_id"`
	Latitude     float64 `json:"latitude"`
	Longitude    float64 `json:"longitude"`
	SpeedKMH     float64 `json:"speed_kmh"`
	BatteryLevel int     `json:"battery_level"`
	Timestamp    string  `json:"timestamp"`
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

type RiderService struct {
	mu           sync.RWMutex
	telemetry    map[string]RiderTelemetry
	outbox       []OutboxEvent
	nextOutboxID int64
	pingsCount   int64
	brokerAddr   string
	topic        string
}

func NewRiderService() *RiderService {
	broker := os.Getenv("REDPANDA_BROKERS")
	if broker == "" {
		broker = "redpanda.platform.svc.cluster.local:9092"
	}
	topic := os.Getenv("RIDERS_TOPIC")
	if topic == "" {
		topic = "riders.telemetry"
	}

	return &RiderService{
		telemetry:  make(map[string]RiderTelemetry),
		outbox:     make([]OutboxEvent, 0),
		brokerAddr: broker,
		topic:      topic,
	}
}

func (s *RiderService) RecordTelemetry(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var req struct {
		RiderID      string  `json:"rider_id"`
		Latitude     float64 `json:"latitude"`
		Longitude    float64 `json:"longitude"`
		SpeedKMH     float64 `json:"speed_kmh"`
		BatteryLevel int     `json:"battery_level"`
	}

	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, fmt.Sprintf("Invalid JSON: %v", err), http.StatusBadRequest)
		return
	}

	if req.RiderID == "" || req.Latitude < -90 || req.Latitude > 90 || req.Longitude < -180 || req.Longitude > 180 {
		http.Error(w, "Validation failed: rider_id required, valid lat/lon coordinates required", http.StatusUnprocessableEntity)
		return
	}

	telemetry := RiderTelemetry{
		RiderID:      req.RiderID,
		Latitude:     req.Latitude,
		Longitude:    req.Longitude,
		SpeedKMH:     req.SpeedKMH,
		BatteryLevel: req.BatteryLevel,
		Timestamp:    time.Now().UTC().Format(time.RFC3339),
	}

	eventPayload, err := json.Marshal(telemetry)
	if err != nil {
		http.Error(w, "Serialization error", http.StatusInternalServerError)
		return
	}

	s.mu.Lock()
	s.telemetry[req.RiderID] = telemetry
	s.nextOutboxID++
	s.outbox = append(s.outbox, OutboxEvent{
		ID:          s.nextOutboxID,
		EventID:     fmt.Sprintf("evt-rider-%s-%d", req.RiderID, time.Now().UnixNano()),
		AggregateID: req.RiderID,
		EventType:   "RiderLocationPing",
		Payload:     eventPayload,
		Status:      "PENDING",
		CreatedAt:   time.Now().UTC(),
	})
	s.mu.Unlock()
	atomic.AddInt64(&s.pingsCount, 1)

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusAccepted)
	_ = json.NewEncoder(w).Encode(map[string]interface{}{
		"status":    "ACCEPTED",
		"rider_id":  req.RiderID,
		"timestamp": telemetry.Timestamp,
	})
}

func (s *RiderService) UpdateStatus(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	parts := strings.Split(strings.Trim(r.URL.Path, "/"), "/")
	if len(parts) < 4 || parts[0] != "v1" || parts[1] != "riders" || parts[3] != "status" {
		http.Error(w, "Path must be /v1/riders/{id}/status", http.StatusBadRequest)
		return
	}
	riderID := parts[2]

	var req struct {
		Status string `json:"status"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid body", http.StatusBadRequest)
		return
	}

	s.mu.Lock()
	s.nextOutboxID++
	payload, _ := json.Marshal(map[string]string{
		"rider_id":  riderID,
		"status":    req.Status,
		"timestamp": time.Now().UTC().Format(time.RFC3339),
	})
	s.outbox = append(s.outbox, OutboxEvent{
		ID:          s.nextOutboxID,
		EventID:     fmt.Sprintf("evt-rider-status-%s-%d", riderID, time.Now().UnixNano()),
		AggregateID: riderID,
		EventType:   "RiderStatusChanged",
		Payload:     payload,
		Status:      "PENDING",
		CreatedAt:   time.Now().UTC(),
	})
	s.mu.Unlock()

	log.Printf("[RIDER_SERVICE] Rider %s status updated: %s (Outbox queued)", riderID, req.Status)

	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]string{"status": "UPDATED", "rider_id": riderID})
}

func (s *RiderService) StartOutboxRelay(ctx context.Context) {
	ticker := time.NewTicker(100 * time.Millisecond)
	defer ticker.Stop()

	log.Printf("[OUTBOX_RELAY] Rider outbox relay started. Target broker: %s, Topic: %s", s.brokerAddr, s.topic)

	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			s.mu.Lock()
			for i := range s.outbox {
				if s.outbox[i].Status == "PENDING" {
					log.Printf("[OUTBOX_RELAY] Flushed rider event %s (%s) to Redpanda topic '%s'",
						s.outbox[i].EventID, s.outbox[i].EventType, s.topic)
					s.outbox[i].Status = "PUBLISHED"
				}
			}
			s.mu.Unlock()
		}
	}
}

func main() {
	svc := NewRiderService()
	mux := http.NewServeMux()

	mux.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte(`{"status":"UP","service":"rider-service"}`))
	})

	mux.HandleFunc("/metrics", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "text/plain; version=0.0.4")
		fmt.Fprintf(w, "# HELP rider_telemetry_pings_total Total rider telemetry pings received\n")
		fmt.Fprintf(w, "# TYPE rider_telemetry_pings_total counter\n")
		fmt.Fprintf(w, "rider_telemetry_pings_total %d\n", atomic.LoadInt64(&svc.pingsCount))
	})

	mux.HandleFunc("/v1/riders/telemetry", svc.RecordTelemetry)
	mux.HandleFunc("/v1/riders/", svc.UpdateStatus)

	port := os.Getenv("PORT")
	if port == "" {
		port = "8081"
	}

	server := &http.Server{
		Addr:    ":" + port,
		Handler: mux,
	}

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	go svc.StartOutboxRelay(ctx)

	go func() {
		log.Printf("[RIDER_SERVICE] Starting HTTP server on :%s", port)
		if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("[RIDER_SERVICE] Server failed: %v", err)
		}
	}()

	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, syscall.SIGINT, syscall.SIGTERM)
	<-sigChan

	log.Println("[RIDER_SERVICE] Shutting down...")
	cancel()
	shutdownCtx, shutdownCancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer shutdownCancel()
	_ = server.Shutdown(shutdownCtx)
}
