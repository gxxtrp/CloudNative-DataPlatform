# Workflow: DLQ Incident Triage & Self-Healing Replay Engine

**Workflow ID**: `dlq-self-healing-replay`  
**Target Role**: Data Platform Engineer  
**Status**: DRAFT - Ready for Implementation  
**Category**: Platform Reliability & Self-Healing SRE  

---

## 1. Objective
Provide an automated incident triage and safe data recovery mechanism for poison pills, corrupt payloads, and schema drift quarantined during streaming ingestion. This workflow clusters dead letters by error signature, prevents duplicate writes, and gives data engineers a dry-run replay engine with decision-ready briefs.

---

## 2. Trigger
- **Event Trigger (Continuous)**: Streaming Ingestion Worker routes unparseable or non-compliant payloads to `platform.dlq.v1` and `s3://Platform-quarantine/`.
- **Threshold Trigger (Alert)**: DLQ ingestion rate exceeds **10 messages/minute** or **> 1% total stream traffic**, firing a Prometheus/Alertmanager incident notification.
- **Manual Trigger**: Data engineer runs `uv run python scripts/dlq_triage.py` or `uv run python scripts/dlq_replay.py`.

---

## 3. Storage & Quarantine Topology
- **Dead-Letter Topic**: `platform.dlq.v1` (Redpanda, 3 partitions, 7-day retention).
- **Dead-Letter Object Store**: `s3://Platform-quarantine/`
  - `/raw/{date}/{message_id}.json` (Original raw bytes, Kafka headers, ingestion timestamp).
  - `/metadata/{date}/{message_id}.meta.json` (Error traceback, failed schema version, error classification).
  - `/replayed/{date}/{message_id}.json` (Archived replayed payloads with replay timestamp and actor).

---

## 4. Execution Steps (Autonomous Pipeline & Replay Engine)

```
       ┌─────────────────────────────────────────────────────────────┐
       │ Ingestion Worker Quarantines Event to `s3://Platform-quarantine`│
       └──────────────────────────────┬──────────────────────────────┘
                                      │
                                      ▼
       ┌─────────────────────────────────────────────────────────────┐
       │ Diagnostic Classifier Groups by Error Fingerprint:          │
       │  - SCHEMA_DRIFT (New/unregistered field from app updates)   │
       │  - TYPE_MISMATCH (String passed for numeric coordinate, etc)│
       │  - CORRUPTED_PAYLOAD (Unparseable JSON, missing entity IDs) │
       └──────────────────────────────┬──────────────────────────────┘
                                      │
                                      ▼
       ┌─────────────────────────────────────────────────────────────┐
       │ Dry-Run Simulation: Re-evaluates against Target Schemas &    │
       │ verifies deduplication against Silver Table (`order_id`)    │
       └──────────────────────────────┬──────────────────────────────┘
                                      │
                                      ▼
       ┌─────────────────────────────────────────────────────────────┐
       │ PUSH RIGHT: Generates Decision-Ready DLQ Incident Brief     │
       └──────────────────────────────┬──────────────────────────────┘
                                      │
                         [ Engineer Reviews Brief ]
                                      │
                                      ▼
       ┌─────────────────────────────────────────────────────────────┐
       │ Execute Replay with `replayed: true` Header & Audit Log     │
       └─────────────────────────────────────────────────────────────┘
```

### Step 1: Automated Triage & Clustering
The triage worker scans unprocessed records in `s3://Platform-quarantine/`:
```bash
uv run python scripts/dlq_triage.py --since 1h
```
- Groups records into error clusters based on exception type and path.
- Flags whether a contract update (e.g. adding an optional field) would resolve the cluster.

### Step 2: Dry-Run Replay Simulation ("Push Right")
Before moving any data, the engineer invokes a dry-run replay:
```bash
uv run python scripts/dlq_replay.py --cluster SCHEMA_DRIFT --dry-run
```
- Reads quarantined events in memory.
- Validates against the latest registered schema in `contracts/schemas/`.
- Queries `s3://Platform-silver-lakehouse/orders_state` via DuckDB to check if each `order_id` already has a newer state (preventing obsolete out-of-order writes).
- Generates the **DLQ Incident Brief**.

---

## 5. Checkpoint & Decision Brief

### Checkpoint Rule
Execution pauses for human review of the Replay Brief before any re-injection into the live streaming pipeline or lakehouse.

### Brief Format
```markdown
### 🛠️ DLQ Incident Triage & Replay Brief
- **Quarantine Window**: Last 60 minutes
- **Total Quarantined Records**: 142 records
- **Failure Taxonomy**:
  - `SCHEMA_DRIFT`: 138 records (Caused by new `rider_app_version: "3.12.0"` adding `battery_level` field)
  - `CORRUPTED_PAYLOAD`: 4 records (Null `order_id`, unrecoverable)
- **Downstream Safety Assessment**:
  - Validatable under updated contract `orders.lifecycle.v1.1.json`: 138 / 138
  - Deduplication Check: 138 records have no existing conflicting final states in Silver Lakehouse.
  - Estimated Replay Throughput: ~25 msgs/sec (zero consumer lag impact)
- **Status**: Dry-run succeeded.
- **Action Required**: Confirm replay of 138 records to `orders.lifecycle.v1` [y/N]?
```

---

## 6. Execution & Audit Log

Upon confirmation:
1. Messages are published back to `orders.lifecycle.v1` with headers:
   - `x-replayed: "true"`
   - `x-original-error: "SCHEMA_DRIFT"`
   - `x-replay-timestamp: "<ISO-8601>"`
2. Replayed payloads in `s3://Platform-quarantine/` are moved to `/replayed/` partition for audit trail.
3. Prometheus counters updated:
   - `pipeline_dlq_replayed_total{status="success"}`

---

## 7. Automated Verification & Definition of Done

1. **Poison Injection**: Ingest 100 invalid events into the stream.
2. **Triage Assertion**: `scripts/dlq_triage.py` correctly groups them by error signature.
3. **Dry-Run Assertion**: `scripts/dlq_replay.py --dry-run` accurately predicts valid count without mutating state.
4. **Replay Assertion**: Approving replay recovers the 100 records into the Silver Iceberg table without creating duplicates or secondary DLQ loops.
