package main

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/google/uuid"
)

type fakeRiderStore struct {
	telemetry RiderTelemetry
	event     OutboxEvent
}

func (s *fakeRiderStore) RecordTelemetry(_ context.Context, telemetry RiderTelemetry, event OutboxEvent) error {
	s.telemetry, s.event = telemetry, event
	return nil
}
func (s *fakeRiderStore) Pending(context.Context, int) ([]OutboxEvent, error) { return nil, nil }
func (s *fakeRiderStore) MarkPublished(context.Context, int64) error          { return nil }
func (s *fakeRiderStore) PendingCount(context.Context) (int, error)           { return 0, nil }
func (s *fakeRiderStore) Close() error                                        { return nil }

func TestRecordTelemetryWritesV2Event(t *testing.T) {
	store := &fakeRiderStore{}
	service := newRiderService(store, nil)
	request := httptest.NewRequest(http.MethodPost, "/v1/riders/telemetry", strings.NewReader(`{"rider_id":"r-1","latitude":13.7563,"longitude":100.5018,"speed_kmh":20,"battery_level":80,"geohash":"w4rw","heading_degrees":90}`))
	recorder := httptest.NewRecorder()

	service.RecordTelemetry(recorder, request)

	if recorder.Code != http.StatusAccepted {
		t.Fatalf("status = %d, want %d", recorder.Code, http.StatusAccepted)
	}
	if _, err := uuid.Parse(store.event.EventID); err != nil {
		t.Fatalf("event ID must be UUID: %v", err)
	}
	var event riderTelemetryEvent
	if err := json.Unmarshal(store.event.Payload, &event); err != nil {
		t.Fatalf("decode event: %v", err)
	}
	if event.SchemaVersion != "2.0.0" || event.Producer != "rider-service" || event.Status != "AVAILABLE" {
		t.Fatalf("unexpected v2 event: %#v", event)
	}
}
