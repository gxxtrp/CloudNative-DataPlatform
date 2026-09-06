# Workflow: Platform SRE Observability & SLA Monitoring

**Workflow ID**: `platform-sre-observability-sla`  
**Target Role**: Data Platform Engineer  
**Status**: DRAFT - Ready for Implementation  
**Category**: SRE, Observability, Telemetry & Alerting  

---

## 1. Objective
Establish comprehensive Site Reliability Engineering (SRE) observability across all layers of the Cloud-Native Data Platform. This workflow continuously tracks ingestion throughput, consumer group lag, end-to-end event freshness percentiles (p50/p95/p99), DLQ error rates, and Lakehouse storage metrics, exposing Prometheus metrics and a pre-seeded, declarative Grafana dashboard.

---

## 2. Trigger
- **Continuous Metrics Scrape**: Prometheus server scrapes exporter endpoints every **10 seconds** in namespace `platform`.
- **Alert Evaluation Trigger**: Prometheus Alertmanager rules evaluated every **30 seconds** against Service Level Objectives (SLOs).
- **Manual Trigger**: `curl http://localhost:9100/metrics` or `make test-metrics`.

---

## 3. Concrete Platform Service Level Objectives (SLOs)
| Objective | Metric Indicator | Target SLA Threshold | Severity |
| :--- | :--- | :--- | :--- |
| **Data Freshness** | `histogram_quantile(0.95, sum(rate(pipeline_e2e_latency_seconds_bucket[5m])) by (le))` | **p95 < 30 seconds** | Warning |
| **Consumer Lag** | `redpanda_consumer_lag_records{group="stream-ingestor-group"}` | **< 500 records** for > 3 min | Warning |
| **Pipeline Reliability**| `rate(pipeline_dlq_events_total[5m]) / rate(pipeline_events_total[5m])` | **< 0.5% DLQ rate** | Critical |
| **Worker Liveness** | `up{job="stream-ingestor"}` | **== 1** | Critical |
| **Storage Hygiene** | `lakehouse_uncompacted_small_files_count` | **< 30 files** per partition | Warning |

---

## 4. Telemetry Architecture & Implementation (The Full Observability Stack)

```
 ┌────────────────────────────────────────────────────────────────────────────────────────┐
 │                              MULTI-TIER TELEMETRY EXPORTERS                            │
 │  Kong Gateway (/metrics)      │  Redpanda Broker (Lag & Offsets)                        │
 │  Order / Rider / Stream Apps  │  Longhorn CSI Storage Metrics                          │
 │  Apache Flink Metrics Reporter│  W3C Distributed Trace Context (traceparent)           │
 └───────────────────────┬───────────────────────────────┬────────────────────────────────┘
                         │                               │
       ┌─────────────────┴─────────────────┐             │
       │ (Prometheus Scrape: 10s)          │ (Pod Logs)  │ (OTLP Traces: 4317/4318)
       ▼                                   ▼             ▼
 ┌───────────────────────────┐    ┌─────────────────┐  ┌──────────────────────────────────┐
 │ PROMETHEUS (TSDB & Rules) │    │ LOKI + PROMTAIL │  │ JAEGER DISTRIBUTED TRACING       │
 │ Namespace: `platform`     │    │ Single-Binary   │  │ All-In-One (OTLP gRPC/HTTP)      │
 │ Port: 9090                │    │ Port: 3100      │  │ UI Port: 31686 (NodePort)        │
 └─────────────┬─────────────┘    └────────┬────────┘  └────────────────┬─────────────────┘
               │                           │                            │
               │ (Alert Trigger)           │                            │
               ▼                           │                            │
 ┌───────────────────────────┐             │                            │
 │ ALERTMANAGER              │             │                            │
 │ Inhibit, Group & Route    │             │                            │
 │ Port: 9093                │             │                            │
 └───────────────────────────┘             │                            │
               │                           │                            │
               └───────────────────┬───────┴────────────────────────────┘
                                   │ (Unified Data Sources)
                                   ▼
 ┌────────────────────────────────────────────────────────────────────────────────────────┐
 │ DECLARATIVE GRAFANA SRE DASHBOARDS (Namespace: `observability`, Port: 30300)           │
 │ Pre-wired Data Sources: Prometheus, Alertmanager, Loki, Jaeger                         │
 │ Auto-mounted Dashboard: `k8s/observability/grafana/base/dashboard-platform-overview-configmap.yaml`│
 └────────────────────────────────────────────────────────────────────────────────────────┘
```

### 4.1 Exported Telemetry Catalog
- **Metrics**: Kong RPS, stream lag, valid vs DLQ event counts, transactional outbox pending queue, rider pings.
- **Logs**: Centralized Loki log stream with structured JSON parsing (`trace_id`, `event_id`, `severity`).
- **Traces**: OpenTelemetry distributed spans across Kong Ingress -> Order/Rider Service -> Redpanda -> Lakehouse.
- **Alerts**: Automated routing of SLO breaches to SRE receivers.

### 4.2 Declarative Grafana Provisioning
- Dashboard specification stored at `k8s/observability/grafana/base/dashboard-platform-overview-configmap.yaml`.
- Automatically provisioned into Grafana via Kubernetes ConfigMap without manual setup.
- Displays:
  - **Ingress Layer**: Kong requests/sec, HTTP 4xx/5xx error rates, API latency.
  - **Streaming Layer**: Flink processing throughput, Redpanda consumer lag by partition.
  - **Domain Workloads**: Orders created, Rider GPS pings, Transactional outbox pending gauge.
  - **Centralized Logs**: Loki live log stream panel querying `{job="kubernetes-pods"}`.
  - **Tracing Bridge**: Direct link to Jaeger UI (`http://localhost:31686`).

---

## 5. Checkpoint & Decision Brief

### Checkpoint Rule
- **Healthy Operation**: Autonomous monitoring and metric logging.
- **SLO Breach Checkpoint**: When Prometheus Alertmanager detects an active SLO violation for > 2 consecutive scrape cycles, it dispatches an **SRE Incident Brief** to the platform engineer.

### Brief Format
```markdown
### 🚨 Data Platform SRE Alert: Consumer Lag & Freshness SLO Breach
- **Alert Name**: `HighConsumerLagAndFreshnessDegradation`
- **Severity**: Warning
- **Impacted Stream**: `orders.lifecycle.v1`
- **Current Metrics**:
  - Consumer Lag: 1,420 records (SLO threshold: < 500 records)
  - P95 End-to-End Latency: 78.4 seconds (SLO threshold: < 30 seconds)
  - Worker CPU Utilization: 92% of 250m limit
- **Probable Root Cause**: Traffic spike or slow Iceberg commit I/O.
- **Recommended Action**:
  - Check worker logs: `kubectl logs -n apps deploy/stream-ingestor`
  - Horizontal pod scale: `kubectl scale deploy/stream-ingestor -n apps --replicas=2`
```

---

## 6. Automated Verification & Definition of Done

1. **Metrics Exposure Assertion**: `curl http://localhost:9100/metrics` returns all 7 custom platform metrics with valid Prometheus exposition formatting.
2. **Grafana Availability Assertion**: Grafana responds on `http://localhost:3000`, the data source points to Prometheus, and the `platform-overview` dashboard renders panels without errors.
3. **Alert Trigger Assertion**: Artificially inject high message volume into Redpanda; verify consumer lag metric rises and triggers the `HighConsumerLag` alert state in Prometheus within 2 minutes.
4. **Memory Guardrail Assertion**: Prometheus and Grafana combined memory consumption remains strictly under 512MiB.
