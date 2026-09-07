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

Consumed by: rider-service-env ExternalSecret -> rider-service deployment.

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

Consumed by: traffic-generator-env ExternalSecret -> traffic-generator deployment.

---

## ExternalSecret to Vault Path Mapping

| ExternalSecret | Namespace | Vault Path | K8s Secret Created |
| --- | --- | --- | --- |
| minio-external-secret | platform | secret/platform/minio | minio-credentials |
| postgres-external-secret | platform | secret/platform/postgres | postgres-credentials |
| grafana-external-secret | observability | secret/observability/grafana | grafana-credentials |
| rider-service-external-secret | apps | secret/apps/rider-service | rider-service-env |
| stream-ingestor-external-secret | apps | secret/apps/stream-ingestor | stream-ingestor-env |
| traffic-generator-external-secret | apps | secret/apps/traffic-generator | traffic-generator-env |

---

## Seeding Secrets & Environment Customization

The platform supports safe, zero-plaintext-in-git secret management with a two-tiered customization model:

### 1. The Reference Template (`.env.example`)
All configurable credential environment variables are documented in [.env.example](file:///c:/Users/x/work/data-platfrom/.env.example). Both `.env` and `.env.*` are strictly gitignored to guarantee private credentials are never committed.

To define custom secrets:
```bash
cp .env.example .env
# Edit .env with custom passwords, ports, or endpoints
```

### 2. Method A: Local Push via CLI (`make seed-secrets`)
When executing commands locally or in WSL against the exposed Vault endpoint (`:38200`):
```bash
make seed-secrets
```
The script [infra/bootstrap/seed-vault.sh](file:///c:/Users/x/work/data-platfrom/infra/bootstrap/seed-vault.sh) sources `.env` (falling back to `.env.example` / defaults if `.env` is absent) and writes all values directly into Vault KV v2.

### 3. Method B: In-Cluster Seeding via ArgoCD Job (`make load-env`)
In automated GitOps deployments, the `vault-secret-seeder` Job ([k8s/security/vault/base/secret-seeder-job.yaml](file:///c:/Users/x/work/data-platfrom/k8s/security/vault/base/secret-seeder-job.yaml)) runs inside the cluster during **Sync Wave -1**.
- Because GitOps cannot read local uncommitted `.env` files from Git, load local secrets into the cluster once:
```bash
make load-env
```
This creates or updates a Kubernetes Secret named `vault-seed-env` in the `vault-system` namespace.
- The `vault-secret-seeder` Job mounts `vault-seed-env` with `optional: true`. If present, custom credentials override the defaults; if absent, the Job safely falls back to standard development credentials without crashing.

