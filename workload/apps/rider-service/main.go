package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"sync/atomic"
	"syscall"
	"time"

	"github.com/google/uuid"
)

type RiderTelemetry struct {
	RiderID      string  `json:"rider_id"`
	Latitude     float64 `json:"latitude"`
	Longitude    float64 `json:"longitude"`
	SpeedKMH     float64 `json:"speed_kmh"`
	BatteryLevel int     `json:"battery_level"`
	Geohash      string  `json:"geohash"`
	Heading      float64 `json:"heading_degrees"`
	Status       string  `json:"rider_status"`
	Timestamp    string  `json:"timestamp"`
}

type riderTelemetryEvent struct {
	EventID        string  `json:"event_id"`
	EventTimestamp string  `json:"event_timestamp"`
	SchemaVersion  string  `json:"schema_version"`
	Producer       string  `json:"producer"`
	RiderID        string  `json:"rider_id"`
	Latitude       float64 `json:"latitude"`
	Longitude      float64 `json:"longitude"`
	Geohash        string  `json:"geohash"`
	SpeedKMH       float64 `json:"speed_kmh"`
	Heading        float64 `json:"heading_degrees"`
	BatteryLevel   int     `json:"battery_level"`
	Status         string  `json:"rider_status"`
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
	store      RiderStore
	publisher  *kafkaRiderPublisher
	pingsCount int64
}

func newRiderService(store RiderStore, publisher *kafkaRiderPublisher) *RiderService {
	return &RiderService{store: store, publisher: publisher}
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
		Geohash      string  `json:"geohash"`
		Heading      float64 `json:"heading_degrees"`
		Status       string  `json:"rider_status"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, fmt.Sprintf("Invalid JSON: %v", err), http.StatusBadRequest)
		return
	}
	if req.RiderID == "" || req.Geohash == "" || req.Latitude < -90 || req.Latitude > 90 || req.Longitude < -180 || req.Longitude > 180 || req.SpeedKMH < 0 || req.Heading < 0 || req.Heading > 360 || req.BatteryLevel < 0 || req.BatteryLevel > 100 {
		http.Error(w, "Validation failed: rider_id required, valid lat/lon coordinates required", http.StatusUnprocessableEntity)
		return
	}
	if req.Status == "" {
		req.Status = "AVAILABLE"
	}
	if !isValidRiderStatus(req.Status) {
		http.Error(w, "Unsupported rider_status", http.StatusUnprocessableEntity)
		return
	}
	telemetry := RiderTelemetry{RiderID: req.RiderID, Latitude: req.Latitude, Longitude: req.Longitude, SpeedKMH: req.SpeedKMH, BatteryLevel: req.BatteryLevel, Geohash: req.Geohash, Heading: req.Heading, Status: req.Status, Timestamp: time.Now().UTC().Format(time.RFC3339)}
	eventID := uuid.NewString()
	payload, err := json.Marshal(newRiderTelemetryEvent(telemetry, eventID))
	if err != nil {
		http.Error(w, "Serialization error", http.StatusInternalServerError)
		return
	}
	event := OutboxEvent{EventID: eventID, AggregateID: telemetry.RiderID, EventType: "RiderTelemetryRecorded", Payload: payload}
	if err := s.store.RecordTelemetry(r.Context(), telemetry, event); err != nil {
		http.Error(w, "Could not persist rider telemetry", http.StatusInternalServerError)
		return
	}
	atomic.AddInt64(&s.pingsCount, 1)
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusAccepted)
	_ = json.NewEncoder(w).Encode(map[string]string{"status": "ACCEPTED", "rider_id": telemetry.RiderID, "timestamp": telemetry.Timestamp})
}

func newRiderTelemetryEvent(telemetry RiderTelemetry, eventID string) riderTelemetryEvent {
	return riderTelemetryEvent{EventID: eventID, EventTimestamp: telemetry.Timestamp, SchemaVersion: "2.0.0", Producer: "rider-service", RiderID: telemetry.RiderID, Latitude: telemetry.Latitude, Longitude: telemetry.Longitude, Geohash: telemetry.Geohash, SpeedKMH: telemetry.SpeedKMH, Heading: telemetry.Heading, BatteryLevel: telemetry.BatteryLevel, Status: telemetry.Status}
}

func isValidRiderStatus(status string) bool {
	return map[string]bool{"OFFLINE": true, "AVAILABLE": true, "EN_ROUTE_TO_MERCHANT": true, "WAITING_AT_MERCHANT": true, "DELIVERING_ORDER": true}[status]
}
func (s *RiderService) StartOutboxRelay(ctx context.Context) {
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
	store, err := newPostgresRiderStore(ctx)
	if err != nil {
		log.Fatalf("[RIDER_SERVICE] durable store: %v", err)
	}
	defer store.Close()
	svc := newRiderService(store, newKafkaRiderPublisher())
	mux := http.NewServeMux()
	mux.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte(`{"status":"UP","service":"rider-service"}`))
	})
	mux.HandleFunc("/metrics", func(w http.ResponseWriter, r *http.Request) {
		pending, _ := store.PendingCount(r.Context())
		w.Header().Set("Content-Type", "text/plain; version=0.0.4")
		fmt.Fprintf(w, "rider_telemetry_pings_total %d\noutbox_pending_events %d\n", atomic.LoadInt64(&svc.pingsCount), pending)
	})
	mux.HandleFunc("/v1/riders/telemetry", svc.RecordTelemetry)
	port := os.Getenv("PORT")
	if port == "" {
		port = "8081"
	}
	server := &http.Server{Addr: ":" + port, Handler: mux, ReadHeaderTimeout: 5 * time.Second}
	go svc.StartOutboxRelay(ctx)
	go func() {
		if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("[RIDER_SERVICE] server: %v", err)
		}
	}()
	<-ctx.Done()
	shutdownCtx, shutdownCancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer shutdownCancel()
	_ = server.Shutdown(shutdownCtx)
}
