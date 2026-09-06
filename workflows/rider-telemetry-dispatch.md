# Workflow: Rider Telemetry & Dispatch Tracker

**Workflow ID**: `rider-telemetry-dispatch`  
**Target Domain**: Rider Fleet Telemetry & Order Assignment  
**Status**: APPROVED - Ready for Implementation  
**Owning Team**: Rider Logistics & Dispatch Engineering (`apps/rider-service`)  

---

## 1. Objective

Provide a high-frequency Go HTTP service to ingest rider GPS telemetry pings (`latitude`, `longitude`, `speed_kmh`, `battery_level`) and manage rider status (`OFFLINE`, `AVAILABLE`, `ASSIGNED`, `ARRIVED_STORE`, `EN_ROUTE`). Persist operational state to PostgreSQL (`riders_db`) with a Transactional Outbox relaying events to Redpanda topic `riders.telemetry`.

---

## 2. Triggers

- **Rider Client Trigger**: Rider mobile applications stream GPS location pings every 5-10 seconds via **Kong Ingress Gateway** (`http://kong-proxy.ingress.svc.cluster.local:80/v1/riders/telemetry`).
- **Dispatch Assignment Trigger**: Dispatch orchestration assigns orders to riders (`POST /v1/riders/{id}/assign`).
- **Outbox Relay Trigger**: Internal goroutine polling every **50ms** drains pending rider telemetry events to Redpanda.

---

## 3. Database Schema (riders_db)

### 3.1 Riders Table (`riders`)
```sql
CREATE TABLE IF NOT EXISTS riders (
    id VARCHAR(64) PRIMARY KEY,
    name VARCHAR(128) NOT NULL,
    vehicle_type VARCHAR(32) DEFAULT 'MOTORCYCLE',
    status VARCHAR(32) DEFAULT 'OFFLINE',
    last_latitude NUMERIC(10, 6),
    last_longitude NUMERIC(10, 6),
    last_ping_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
```

### 3.2 Outbox Table (`rider_outbox`)
```sql
CREATE TABLE IF NOT EXISTS rider_outbox (
    id BIGSERIAL PRIMARY KEY,
    event_id VARCHAR(64) UNIQUE NOT NULL,
    aggregate_id VARCHAR(64) NOT NULL,
    event_type VARCHAR(64) NOT NULL,
    payload JSONB NOT NULL,
    status VARCHAR(16) DEFAULT 'PENDING',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    published_at TIMESTAMP WITH TIME ZONE
);
CREATE INDEX IF NOT EXISTS idx_rider_outbox_pending ON rider_outbox (id) WHERE status = 'PENDING';
```

---

## 4. Definition of Done

An implementer agent completes this workflow when:
1. `apps/rider-service` compiles as an autonomous Go service with its own `Dockerfile`.
2. HTTP endpoints `POST /v1/riders/telemetry` and `POST /v1/riders/{id}/status` atomically record telemetry and outbox events.
3. Outbox background relay publishes events conforming to `contracts/schemas/riders/riders.telemetry.v1.json` to Redpanda topic `riders.telemetry`.
4. Deployed via `k8s/apps/rider-service/` and exposed via Kong Gateway API `HTTPRoute`.
