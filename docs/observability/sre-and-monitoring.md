# Observability: Full Stack Telemetry & SRE SLOs

**Domain**: Platform SRE & Observability (`k8s/observability/`, `argocd/*/observability/`)  
**Scope**: The Three Pillars (Metrics, Logs, Traces) + Alerting & Correlated SRE Dashboards  

---

## 1. Full Observability Architecture

The observability stack is decoupled into 5 first-class platform services running in namespace `observability`:

```mermaid
flowchart TD
    subgraph Exporters["Telemetry Exporters"]
        GW[Kong Ingress Gateway :8100/metrics]
        APPS[Go Workloads :8080, :8081, :8082 /metrics]
        RP[Redpanda Broker :9644/public_metrics]
        PODS[Container stdout/stderr logs]
    end

    subgraph Core["Observability Engines (Namespace: observability)"]
        PROM[Prometheus TSDB :9090]
        AM[Alertmanager :9093]
        LOKI[Loki Log Aggregator :3100]
        PTL[Promtail DaemonSet]
        JAEGER[Jaeger Tracing :16686 / :4317]
    end

    subgraph UI["SRE Visualization"]
        GRAFANA[Grafana Dashboard :30300]
    end

    GW & APPS & RP -->|Scrape /metrics| PROM
    PODS -->|Tail /var/log/pods| PTL -->|Push| LOKI
    GW & APPS -->|OTLP Tracing| JAEGER

    PROM -->|Evaluate SLO Rules| AM
    PROM & AM & LOKI & JAEGER -->|Correlated DataSources| GRAFANA
```

---

## 2. Concrete Service Level Objectives (SLOs)

| Objective | Metric Indicator | Target SLA | Severity |
| :--- | :--- | :--- | :--- |
| **Data Freshness** | `histogram_quantile(0.95, sum(rate(pipeline_e2e_latency_seconds_bucket[5m])) by (le))` | **p95 < 30 seconds** | Warning |
| **Consumer Lag** | `redpanda_consumer_lag_records{group="stream-ingestor-group"}` | **< 500 records** for > 3m | Warning |
| **Pipeline Reliability**| `rate(pipeline_dlq_events_total[5m]) / rate(pipeline_events_total[5m])` | **< 0.5% DLQ rate** | Critical |
| **Worker Liveness** | `up{job="stream-ingestor"}` | **== 1** | Critical |
| **Storage Hygiene** | `lakehouse_uncompacted_small_files_count` | **< 30 files** per partition | Warning |

---

## 3. Operational Web UIs & Endpoints

| Component | UI / Endpoint | Default Port | Protocol |
| :--- | :--- | :--- | :--- |
| **Grafana** | `http://localhost:30300` | 30300 (NodePort) | HTTP UI |
| **Jaeger Tracing** | `http://localhost:31686` | 31686 (NodePort) | HTTP UI |
| **Prometheus TSDB**| `http://localhost:9090` | 9090 (ClusterIP) | HTTP / Web |
| **Alertmanager** | `http://localhost:9093` | 9093 (ClusterIP) | HTTP / Web |
| **Loki API** | `http://localhost:3100` | 3100 (ClusterIP) | HTTP REST |
