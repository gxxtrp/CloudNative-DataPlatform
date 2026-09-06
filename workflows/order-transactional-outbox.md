# Workflow: Order Service & Transactional Outbox Pattern

**Workflow ID**: `order-transactional-outbox`  
**Target Domain**: Food Delivery Order Lifecycle & Ingress  
**Status**: APPROVED - Ready for Implementation  
**Owning Team**: Order Checkout & Transactional Engineering (`apps/order-service`)  

---

## 1. Objective

Provide a resilient, high-throughput Go REST API for managing the food delivery order lifecycle (`PLACED`, `CONFIRMED`, `PREPARING`, `READY_FOR_PICKUP`, `DELIVERED`, `CANCELLED`). Persist order state atomically alongside domain events using the **Transactional Outbox Pattern** in PostgreSQL, eliminating dual-write inconsistencies and guaranteeing at-least-once event delivery to Redpanda topic `orders.lifecycle`.

---

## 2. Triggers

- **External Client Trigger**: Client apps (Customer Mobile App, Merchant POS) make HTTP POST requests via **Kong Ingress Gateway** (`http://kong-proxy.ingress.svc.cluster.local:80/v1/orders`).
- **Internal Goroutine Trigger**: Continuous background outbox poller runs every **50ms - 100ms** to drain pending outbox records to Redpanda.

---

## 3. Architectural Seam & Data Flow

```
┌─────────────────────────┐
│ Client App / Merchant   │
└────────────┬────────────┘
             │ HTTP POST /v1/orders
             ▼
┌─────────────────────────┐
│ Kong Gateway API        │ (Route: /v1/orders -> order-service:8080)
└────────────┬────────────┘
             │
             ▼
┌────────────────────────────────────────────────────────┐
│ Order Service (apps/order-service)                     │
│                                                        │
│  1. Validate payload against Data Contracts            │
│  2. Begin PostgreSQL Transaction                       │
│     ├── INSERT INTO orders (id, customer, merchant...) │
│     └── INSERT INTO order_outbox (event_id, payload...)│
│  3. Commit Transaction                                 │
│                                                        │
│  Background Outbox Relay Goroutine:                    │
│     ├── SELECT FROM order_outbox WHERE status='PENDING'│
│     ├── Publish to Redpanda (orders.lifecycle)         │
│     └── UPDATE order_outbox SET status='PUBLISHED'     │
└────────────┬─────────────────────────────┬─────────────┘
             │                             │
             ▼                             ▼
   ┌───────────────────┐         ┌─────────────────────────┐
   │ PostgreSQL        │         │ Redpanda Broker         │
   │ orders_db         │         │ Topic: orders.lifecycle │
   └───────────────────┘         └─────────────────────────┘
```

---

## 4. Database Schema (orders_db)

### 4.1 Orders Table (`orders`)
```sql
CREATE TABLE IF NOT EXISTS orders (
    id VARCHAR(64) PRIMARY KEY,
    customer_id VARCHAR(64) NOT NULL,
    merchant_id VARCHAR(64) NOT NULL,
    amount NUMERIC(12, 2) NOT NULL,
    currency VARCHAR(3) DEFAULT 'THB',
    status VARCHAR(32) NOT NULL,
    delivery_address TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
```

### 4.2 Outbox Table (`order_outbox`)
```sql
CREATE TABLE IF NOT EXISTS order_outbox (
    id BIGSERIAL PRIMARY KEY,
    event_id VARCHAR(64) UNIQUE NOT NULL,
    aggregate_id VARCHAR(64) NOT NULL,
    event_type VARCHAR(64) NOT NULL,
    payload JSONB NOT NULL,
    status VARCHAR(16) DEFAULT 'PENDING',
    retry_count INT DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    published_at TIMESTAMP WITH TIME ZONE
);
CREATE INDEX IF NOT EXISTS idx_outbox_pending ON order_outbox (id) WHERE status = 'PENDING';
```

---

## 5. Definition of Done

An implementer agent completes this workflow when:
1. `apps/order-service` compiles as an autonomous Go service with its own `Dockerfile`.
2. HTTP endpoints `POST /v1/orders` and `POST /v1/orders/{id}/status` successfully persist order records and outbox events in a single atomic transaction.
3. Outbox background relay successfully publishes serialized events matching `contracts/schemas/orders/orders.lifecycle.v1.json` to Redpanda.
4. Kubernetes manifests in `k8s/apps/order-service/` deploy the service and register routes with Kong Gateway API.
