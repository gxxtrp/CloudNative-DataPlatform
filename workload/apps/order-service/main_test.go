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

type fakeOrderStore struct {
	order Order
	event OutboxEvent
}

func (s *fakeOrderStore) Create(_ context.Context, order Order, event OutboxEvent) error {
	s.order, s.event = order, event
	return nil
}
func (s *fakeOrderStore) UpdateStatus(_ context.Context, _ string, _ string, _ OutboxEvent) (Order, error) {
	return Order{}, nil
}
func (s *fakeOrderStore) Pending(context.Context, int) ([]OutboxEvent, error) { return nil, nil }
func (s *fakeOrderStore) MarkPublished(context.Context, int64) error          { return nil }
func (s *fakeOrderStore) PendingCount(context.Context) (int, error)           { return 0, nil }
func (s *fakeOrderStore) Close() error                                        { return nil }

func TestCreateOrderWritesV2LifecycleEvent(t *testing.T) {
	store := &fakeOrderStore{}
	service := newOrderService(store, nil)
	request := httptest.NewRequest(http.MethodPost, "/v1/orders", strings.NewReader(`{"order_id":"o-1","customer_id":"c-1","merchant_id":"m-1","amount":99.5,"items":[{"item_id":"i-1","name":"Rice","price":99.5,"quantity":1}]}`))
	recorder := httptest.NewRecorder()

	service.CreateOrder(recorder, request)

	if recorder.Code != http.StatusCreated {
		t.Fatalf("status = %d, want %d", recorder.Code, http.StatusCreated)
	}
	if store.order.Status != "CREATED" || store.order.PaymentMethod != "CASH_ON_DELIVERY" {
		t.Fatalf("unexpected persisted order: %#v", store.order)
	}
	if _, err := uuid.Parse(store.event.EventID); err != nil {
		t.Fatalf("event ID must be UUID: %v", err)
	}
	var event orderLifecycleEvent
	if err := json.Unmarshal(store.event.Payload, &event); err != nil {
		t.Fatalf("decode event: %v", err)
	}
	if event.SchemaVersion != "2.0.0" || event.Producer != "order-service" || event.Items[0].ItemName != "Rice" {
		t.Fatalf("unexpected v2 event: %#v", event)
	}
}
