# CloudNative Data Platform

A production-ready data platform on GCP using Kubernetes-native tools.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  SOURCE SYSTEMS                                                             │
│  Cloud SQL PostgreSQL, Application Services                                 │
└─────────────────────────────────────────────────────────────────────────────┘
                    │
                    │ CDC (Debezium)
                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                         DATA PLATFORM                                       │
│                                                                             │
│  ┌─────────────┐   ┌─────────────┐   ┌─────────────┐   ┌─────────────┐      │
│  │  Pub/Sub    │ → │  Spark      │ → │    GCS      │ → │  BigQuery   │      │
│  │  (events)   │   │  (ETL)      │   │  (Iceberg)  │   │  (BigLake)  │      │
│  └─────────────┘   └─────────────┘   └─────────────┘   └─────────────┘      │
│        ↑                                                      │             │
│        │                                                      ▼             │
│  ┌─────────────┐                                       ┌─────────────┐      │
│  │  Debezium   │                                       │    DBT      │      │
│  │  (CDC)      │                                       │  (transforms)│     │
│  └─────────────┘                                       └─────────────┘      │
│                                                                             │
│  Orchestration: Argo Workflows    Catalog: OpenMetadata                     │
│  GitOps: ArgoCD                   Monitoring: Prometheus + Grafana          │
└─────────────────────────────────────────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  END USERS                                                                  │
│  Analysts (BigQuery), Data Scientists, BI Tools                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Tech Stack

| Component | Technology | Deployment |
|-----------|------------|------------|
| IaC | Terraspace | GitHub Actions |
| Event Streaming | Pub/Sub | Managed (GCP) |
| CDC | Debezium | GKE |
| Batch Processing | Spark + Spark Operator | GKE |
| Stream Processing | Flink + Flink Operator | GKE |
| Orchestration | Argo Workflows | GKE |
| GitOps | ArgoCD | GKE |
| Lake Storage | GCS + Apache Iceberg | Managed (GCP) |
| Iceberg Catalog | BigQuery Metastore | Managed (GCP) |
| Query Engine | BigQuery (BigLake) | Managed (GCP) |
| Transforms | DBT Core | GKE (via Argo) |
| Data Catalog | OpenMetadata | GKE |
| Monitoring | Prometheus + Grafana | GKE |
| Secrets | External Secrets Operator + GCP Secret Manager | GKE + Managed |
| Container Registry | Artifact Registry | Managed (GCP) |

## Repository Structure

```
CloudNative-DataPlatform/
├── infrastructure/          # Platform team owns — Terraspace
├── platform/                # Platform team owns — K8s platform services
├── pipelines/               # Domain teams own — Data pipelines
├── dbt/                     # Domain teams own — SQL transforms
├── orchestration/           # Shared — Argo workflow templates
├── images/                  # Shared — Docker images
├── .github/                 # CI/CD
└── docs/                    # Documentation
```

See [docs/repository-structure.md](docs/repository-structure.md) for detailed breakdown.

## Environments

| Environment | GCP Project | Purpose |
|-------------|-------------|---------|
| dev | `dataplatform-dev` | Development, experimentation |
| staging | `dataplatform-staging` | Pre-production testing |
| prod | `dataplatform-prod` | Production workloads |

## Quick Start

### Prerequisites

- GCP account with billing enabled
- `gcloud` CLI configured
- `terraspace` installed
- `kubectl` installed
- `argocd` CLI installed

### 1. Bootstrap Infrastructure

```bash
cd infrastructure
export TS_ENV=dev
terraspace up gke
terraspace up networking
terraspace up bigquery
```

### 2. Deploy Platform Services

```bash
# ArgoCD bootstraps itself and other services
kubectl apply -f platform/argocd/bootstrap/
```

### 3. Deploy a Pipeline

```bash
# Domain team submits Argo workflow
argo submit orchestration/workflows/trips/daily-etl.yaml
```

## Team Ownership

| Path | Owner | Responsibility |
|------|-------|----------------|
| `infrastructure/` | Platform Team | GCP resources, GKE, networking |
| `platform/` | Platform Team | K8s operators, monitoring, catalog |
| `pipelines/domains/*/` | Domain Teams | Domain-specific Spark/Flink jobs |
| `dbt/models/domains/*/` | Domain Teams | Domain-specific SQL transforms |
| `orchestration/` | Shared | Workflow templates |

See [CODEOWNERS](.github/CODEOWNERS) for PR review assignments.

## Documentation

- [Repository Structure](docs/repository-structure.md)
- [Design Decisions](docs/design/)
- [Getting Started](docs/getting-started.md)
- [Contributing](docs/contributing.md)
