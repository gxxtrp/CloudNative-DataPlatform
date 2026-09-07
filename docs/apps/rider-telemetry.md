# Workloads: Rider Telemetry & Dispatch Service

**Domain**: Autonomous Domain Engineering (`apps/rider-service`)  
**Scope**: High-Frequency GPS Ingestion, Spatial Precision-7 Geohashing, and Rider Status State Machine  

> [!NOTE]
> **Implementation Status: Architectural Simulation & Contract Specification**  
> The runtime service in `apps/rider-service` is currently implemented as an **architectural prototype / in-memory simulation**. It provides live HTTP endpoints (`/v1/riders/telemetry`, `/v1/riders/{id}/status`), Prometheus metrics, and in-memory outbox queuing. Wire-level Redpanda streaming and Apache Flink geospatial streaming represent target production architectures specified by the formal Data Contract ([`contracts/schemas/riders/riders.telemetry.v1.json`](../../contracts/schemas/riders/riders.telemetry.v1.json)).

---

## 1. Overview & Target Data Flow

The `rider-service` is designed to ingest continuous spatial location pings emitted by mobile couriers. Each ping captures GPS coordinates, compass heading, instantaneous velocity (km/h), and device battery levels:

```mermaid
flowchart LR
    COURIER[Courier Mobile App] -->|GPS Ping every 5-10s| KONG[Kong Ingress Gateway]
    KONG --> RDR[rider-service :8081]
    
    subgraph Storage["Atomic Outbox Storage"]
        RDR -->|Update State| RIDERS[riders table (In-Memory Prototype)]
        RDR -->|Queue Event| OUTBOX[rider_outbox table (In-Memory Prototype)]
    end

    OUTBOX -->|Simulated Relay Log| RP[Redpanda Broker<br/>Topic: riders.telemetry.v1]
    RP -.-> FLINK[Apache Flink Geohash Aggregate (Target Design)]
```

---

## 2. Spatial Geohashing & State Machine Design

- **Spatial Geohash**: Telemetry coordinates conform to Precision-7 Geohashing (~150m accuracy) defined in the data contract, designed for geospatial radius queries and driver clustering without expensive geometric joins.
- **Rider Status State Machine**:
  - `OFFLINE` ➔ `AVAILABLE` ➔ `ASSIGNED` ➔ `ARRIVED_STORE` ➔ `PICKED_UP` ➔ `EN_ROUTE` ➔ `DELIVERED`

---

## 3. Prototype vs. Production Architecture

| Dimension | Current Prototype (`apps/rider-service`) | Target Production Design |
| :--- | :--- | :--- |
| **Ingestion Protocol** | Native Go HTTP (`/v1/riders/telemetry`) | Kong API Gateway Ingress with rate limiting |
| **Outbox Storage** | In-memory thread-safe Go slice (`sync.RWMutex`) | PostgreSQL transactional table with CDC |
| **Broker Streaming** | Background relay loop with structured stdout logging | Real Redpanda Kafka wire-protocol producer (`twmb/franz-go`) |
| **Spatial Indexing** | Coordinate range validation (`-90 <= lat <= 90`) | Real-time geohash encoding and spatial indexing |
| **Data Contract** | Validated via `contracts/schemas/riders/riders.telemetry.v1.json` | Validated via schema registry & inline gateway |

---

## 4. Metrics & Monitoring

Exposes Prometheus metrics on `:8081/metrics`:
- `rider_telemetry_pings_total`: Total GPS telemetry pings processed.
- `/healthz`: Liveness and readiness probe endpoint.
