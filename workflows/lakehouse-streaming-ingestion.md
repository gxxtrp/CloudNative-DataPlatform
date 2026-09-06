# Workflow: Lakehouse Streaming Ingestion & DLQ Quarantine

**Workflow ID**: `lakehouse-streaming-ingestion`  
**Target Domain**: Real-Time Ingestion, Schema Governance & Lakehouse Bronze  
**Status**: APPROVED - Ready for Implementation  
**Owning Team**: Core Data Platform Engineering (`apps/stream-ingestor`)  

---

## 1. Objective

Consume real-time event streams from Redpanda (`orders.lifecycle` and `riders.telemetry`), enforce strict Draft-07 data contract conformance using `santhosh-tekuri/jsonschema/v5`, micro-batch valid events into columnar **Parquet** files written directly to MinIO Bronze Lakehouse (`s3://lakehouse-bronze/`), and isolate schema-violating or corrupted payloads to Redpanda topic `dead.letter.queue`.

---

## 2. Triggers

- **Event Stream Trigger**: Continuous Kafka consumer loop reads batches from Redpanda.
- **Micro-Batch Flush Trigger**: In-memory buffer flushes to MinIO Parquet when:
  - Batch size reaches **500 records**, OR
  - Time elapsed reaches **15 seconds**.

---

## 3. Execution Pipeline

```
┌────────────────────────────────────────────────────────┐
│ Redpanda Topics (orders.lifecycle, riders.telemetry)   │
└───────────────────────────┬────────────────────────────┘
                            │ Kafka Consumer (Consumer Group: stream-ingestor)
                            ▼
┌────────────────────────────────────────────────────────┐
│ Stream Ingestor (apps/stream-ingestor in Go)          │
│                                                        │
│  For each incoming message:                            │
│  1. Validate against Draft-07 JSON Schema              │
│     ├── PASSED ➔ Add to in-memory Parquet record buffer│
│     └── FAILED ➔ Package DeadLetterPayload             │
│                  ➔ Produce to 'dead.letter.queue' topic│
│                                                        │
│  When Buffer full (500 events) or 15s elapsed:         │
│     └── Encode buffer into Parquet file                │
│     └── PutObject into MinIO Bronze S3 bucket          │
│         Path: s3://lakehouse-bronze/orders/            │
│               date=YYYY-MM-DD/part-HHMMSS-<uuid>.parquet
└───────────────────────────┬────────────────────────────┘
                            │
             ┌──────────────┴──────────────┐
             ▼                             ▼
 ┌──────────────────────┐      ┌─────────────────────────┐
 │ MinIO Lakehouse S3   │      │ Redpanda Topic          │
 │ s3://lakehouse-bronze│      │ dead.letter.queue       │
 └──────────────────────┘      └─────────────────────────┘
```

---

## 4. Definition of Done

An implementer agent completes this workflow when:
1. `apps/stream-ingestor` compiles as an autonomous Go service with its own `Dockerfile`.
2. Valid orders and rider events are written to `s3://lakehouse-bronze/orders/` and `s3://lakehouse-bronze/riders/` as readable Parquet files.
3. Injected schema violations (e.g. negative amounts, missing required attributes) are rejected and routed to `dead.letter.queue`.
4. Deployed as an autonomous Kubernetes workload in `k8s/apps/stream-ingestor/` and managed via ArgoCD.
