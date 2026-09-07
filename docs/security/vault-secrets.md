# Vault Secret Requirements

All secrets consumed by the platform are pulled at runtime via the **External Secrets Operator** from HashiCorp Vault KV v2 (secret/ engine).
**No values are stored in git.** This file is the single source of truth for what secrets must be created in Vault before workloads can start.

> **Convention**: vault kv put secret/<path> <key>=<value>
> KV engine path prefix is always secret/ (v2).

---

## Platform

### secret/platform/minio

| Key | Description |
| --- | --- |
| access-key | MinIO root user / S3 access key ID |
| secret-key | MinIO root password / S3 secret access key |
| endpoint | Internal S3 endpoint e.g. http://minio.platform.svc.cluster.local:9000 |

Consumed by: minio-credentials ExternalSecret -> minio deployment, minio init job, lakehouse-compactor cronjob.

---

### secret/platform/postgres

| Key | Description |
| --- | --- |
| password | PostgreSQL superuser password (POSTGRES_PASSWORD) |

Consumed by: postgres-credentials ExternalSecret -> postgres deployment.

---

## Observability

### secret/observability/grafana

| Key | Description |
| --- | --- |
| admin-user | Grafana admin username (GF_SECURITY_ADMIN_USER) |
| admin-password | Grafana admin password (GF_SECURITY_ADMIN_PASSWORD) |

Consumed by: grafana-credentials ExternalSecret -> grafana deployment.

---

## Apps

### secret/apps/order-service

| Key | Description |
| --- | --- |
| PORT | HTTP listen port |
| REDPANDA_BROKERS | Kafka-compatible broker address |
| ORDERS_TOPIC | Redpanda topic name for order events |

Consumed by: order-service-env ExternalSecret -> order-service deployment.

---

### secret/apps/rider-service

| Key | Description |
| --- | --- |
| PORT | HTTP listen port |
| REDPANDA_BROKERS | Kafka-compatible broker address |
| RIDERS_TOPIC | Redpanda topic name for rider telemetry |

Consumed by: 
ider-service-env ExternalSecret -> 
ider-service deployment.

---

### secret/apps/stream-ingestor

| Key | Description |
| --- | --- |
| PORT | HTTP listen port |
| REDPANDA_BROKERS | Kafka-compatible broker address |
| MINIO_ENDPOINT | S3/MinIO endpoint URL |
| BRONZE_BUCKET | Target landing bucket name |

Consumed by: stream-ingestor-env ExternalSecret -> stream-ingestor deployment.

---

### secret/apps/traffic-generator

| Key | Description |
| --- | --- |
| KONG_GATEWAY_URL | Kong proxy base URL |

Consumed by: 	raffic-generator-env ExternalSecret -> 	raffic-generator deployment.

---

## ExternalSecret to Vault Path Mapping

| ExternalSecret | Namespace | Vault Path | K8s Secret Created |
| --- | --- | --- | --- |
| minio-external-secret | platform | secret/platform/minio | minio-credentials |
| postgres-external-secret | platform | secret/platform/postgres | postgres-credentials |
| grafana-external-secret | observability | secret/observability/grafana | grafana-credentials |
| order-service-external-secret | apps | secret/apps/order-service | order-service-env |
| 
ider-service-external-secret | apps | secret/apps/rider-service | 
ider-service-env |
| stream-ingestor-external-secret | apps | secret/apps/stream-ingestor | stream-ingestor-env |
| 	raffic-generator-external-secret | apps | secret/apps/traffic-generator | 	raffic-generator-env |
