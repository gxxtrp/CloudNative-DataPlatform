# Repository Structure

This monorepo uses a **hybrid layout**: shared infrastructure owned by the platform team, domain-specific pipelines owned by domain teams.

## Directory Tree

```
CloudNative-DataPlatform/
│
├── infrastructure/                    # PLATFORM TEAM — Terraspace IaC
│   ├── Gemfile                        # Terraspace dependencies
│   ├── Terrafile                      # Terraform module sources
│   ├── config/
│   │   └── terraform/
│   │       ├── backend.tf             # GCS backend config
│   │       └── provider.tf            # Google provider config
│   │
│   ├── app/
│   │   ├── modules/                   # Reusable Terraform modules
│   │   │   ├── gke-cluster/
│   │   │   ├── gke-nodepool/
│   │   │   ├── pubsub-topic/
│   │   │   ├── bigquery-dataset/
│   │   │   ├── gcs-bucket/
│   │   │   ├── cloud-sql/
│   │   │   ├── artifact-registry/
│   │   │   ├── secret-manager/
│   │   │   └── iam/
│   │   │
│   │   └── stacks/                    # Deployable stacks
│   │       ├── networking/            # VPC, subnets, Cloud NAT
│   │       ├── gke/                   # GKE cluster + node pools
│   │       ├── pubsub/                # Pub/Sub topics
│   │       ├── bigquery/              # Datasets, BigLake connections
│   │       ├── storage/               # GCS buckets (lake)
│   │       ├── secrets/               # Secret Manager secrets
│   │       └── iam/                   # Service accounts, IAM bindings
│   │
│   └── config/env/                    # Environment-specific configs
│       ├── dev.tfvars
│       ├── staging.tfvars
│       └── prod.tfvars
│
├── platform/                          # PLATFORM TEAM — K8s platform services
│   ├── argocd/
│   │   ├── bootstrap/                 # ArgoCD self-bootstrap
│   │   │   └── install.yaml
│   │   └── applications/              # ArgoCD Application CRDs
│   │       ├── platform-apps.yaml     # App-of-apps for platform
│   │       └── domain-apps.yaml       # App-of-apps for domains
│   │
│   ├── operators/                     # K8s operators (Helm/Kustomize)
│   │   ├── spark-operator/
│   │   │   ├── base/
│   │   │   └── overlays/
│   │   │       ├── dev/
│   │   │       ├── staging/
│   │   │       └── prod/
│   │   ├── flink-operator/
│   │   ├── argo-workflows/
│   │   └── external-secrets/
│   │
│   ├── debezium/                      # Debezium deployment
│   │   ├── base/
│   │   │   ├── deployment.yaml
│   │   │   ├── configmap.yaml         # Connector configs
│   │   │   └── service.yaml
│   │   └── overlays/
│   │       ├── dev/
│   │       ├── staging/
│   │       └── prod/
│   │
│   ├── openmetadata/                  # Data catalog
│   │   ├── base/
│   │   └── overlays/
│   │
│   ├── monitoring/                    # Observability stack
│   │   ├── prometheus/
│   │   ├── grafana/
│   │   │   └── dashboards/
│   │   └── alertmanager/
│   │
│   └── namespaces/                    # Namespace definitions
│       ├── platform.yaml
│       ├── orchestration.yaml
│       ├── streaming.yaml
│       ├── batch.yaml
│       └── monitoring.yaml
│
├── pipelines/                         # DOMAIN TEAMS — Data pipelines
│   ├── shared/                        # Shared utilities
│   │   ├── spark/
│   │   │   └── common/                # Common Spark code
│   │   └── flink/
│   │       └── common/                # Common Flink code
│   │
│   └── domains/
│       ├── trips/                     # TRIPS DOMAIN TEAM
│       │   ├── spark/
│       │   │   ├── src/
│       │   │   │   └── bronze_to_silver.py
│       │   │   ├── tests/
│       │   │   ├── pyproject.toml
│       │   │   └── Dockerfile
│       │   ├── flink/
│       │   │   ├── src/
│       │   │   │   └── TripStreamingJob.java
│       │   │   ├── pom.xml
│       │   │   └── Dockerfile
│       │   └── README.md
│       │
│       ├── payments/                  # PAYMENTS DOMAIN TEAM
│       │   ├── spark/
│       │   ├── flink/
│       │   └── README.md
│       │
│       └── users/                     # USERS DOMAIN TEAM
│           ├── spark/
│           └── README.md
│
├── dbt/                               # DOMAIN TEAMS — SQL transforms
│   ├── dbt_project.yml
│   ├── profiles.yml.example
│   ├── packages.yml
│   │
│   ├── models/
│   │   ├── staging/                   # 1:1 with source tables
│   │   │   ├── trips/
│   │   │   │   ├── _trips__sources.yml
│   │   │   │   └── stg_trips.sql
│   │   │   ├── payments/
│   │   │   └── users/
│   │   │
│   │   ├── intermediate/              # Business logic
│   │   │   ├── trips/
│   │   │   │   └── int_trips_enriched.sql
│   │   │   └── payments/
│   │   │
│   │   └── marts/                     # Gold layer
│   │       ├── core/                  # Shared dimensions
│   │       │   ├── dim_date.sql
│   │       │   └── dim_cities.sql
│   │       ├── trips/                 # TRIPS DOMAIN
│   │       │   ├── fact_trips.sql
│   │       │   └── agg_city_daily.sql
│   │       └── payments/              # PAYMENTS DOMAIN
│   │           └── fact_payments.sql
│   │
│   ├── tests/                         # Custom data tests
│   │   └── assert_positive_fares.sql
│   │
│   ├── macros/                        # Reusable SQL macros
│   │   └── generate_surrogate_key.sql
│   │
│   └── Dockerfile                     # DBT container image
│
├── orchestration/                     # SHARED — Argo Workflows
│   ├── templates/                     # Reusable workflow templates
│   │   ├── spark-job.yaml             # Template for Spark jobs
│   │   ├── dbt-run.yaml               # Template for DBT runs
│   │   └── data-quality.yaml          # Template for quality checks
│   │
│   ├── workflows/
│   │   ├── trips/
│   │   │   ├── daily-etl.yaml         # Trips daily pipeline
│   │   │   └── backfill.yaml
│   │   ├── payments/
│   │   │   └── daily-etl.yaml
│   │   └── platform/
│   │       └── openmetadata-ingestion.yaml
│   │
│   └── cron/                          # CronWorkflow definitions
│       ├── trips-daily.yaml
│       └── payments-daily.yaml
│
├── images/                            # Docker images
│   ├── spark-base/
│   │   └── Dockerfile
│   ├── flink-base/
│   │   └── Dockerfile
│   ├── dbt/
│   │   └── Dockerfile
│   └── debezium/
│       └── Dockerfile
│
├── .github/
│   ├── CODEOWNERS                     # PR review ownership
│   ├── workflows/
│   │   ├── infrastructure.yaml        # Terraspace CI/CD
│   │   ├── platform.yaml              # Platform services CI/CD
│   │   ├── pipelines-trips.yaml       # Trips domain CI/CD
│   │   ├── pipelines-payments.yaml    # Payments domain CI/CD
│   │   ├── dbt.yaml                   # DBT CI/CD
│   │   └── images.yaml                # Docker image builds
│   └── pull_request_template.md
│
├── scripts/                           # Utility scripts
│   ├── bootstrap-env.sh               # Initial environment setup
│   ├── port-forward.sh                # Dev access to services
│   └── run-local-dbt.sh               # Local DBT development
│
├── docs/
│   ├── design/
│   │   └── data-platform/             # Design documents
│   ├── getting-started.md
│   ├── contributing.md
│   ├── repository-structure.md        # This file
│   └── runbooks/
│       ├── deploy-new-domain.md
│       └── troubleshooting.md
│
├── .gitignore
├── .pre-commit-config.yaml
├── CODEOWNERS → .github/CODEOWNERS
└── README.md
```

## Ownership Model

### Platform Team Owns

| Path | Description |
|------|-------------|
| `infrastructure/` | All GCP resources via Terraspace |
| `platform/` | K8s operators, monitoring, catalog |
| `images/*-base/` | Base Docker images |
| `orchestration/templates/` | Reusable workflow templates |

### Domain Teams Own

| Path | Owner | Description |
|------|-------|-------------|
| `pipelines/domains/trips/` | Trips Team | Spark/Flink jobs for trips |
| `pipelines/domains/payments/` | Payments Team | Spark/Flink jobs for payments |
| `dbt/models/*/trips/` | Trips Team | DBT models for trips |
| `dbt/models/*/payments/` | Payments Team | DBT models for payments |
| `orchestration/workflows/trips/` | Trips Team | Workflow definitions |

### Shared

| Path | Description |
|------|-------------|
| `pipelines/shared/` | Common utilities used by all domains |
| `dbt/models/marts/core/` | Shared dimensions (dim_date, etc.) |
| `dbt/macros/` | Shared DBT macros |

## Adding a New Domain

1. Create domain folders:
   ```bash
   mkdir -p pipelines/domains/{domain}/spark/src
   mkdir -p pipelines/domains/{domain}/flink/src
   mkdir -p dbt/models/staging/{domain}
   mkdir -p dbt/models/intermediate/{domain}
   mkdir -p dbt/models/marts/{domain}
   mkdir -p orchestration/workflows/{domain}
   ```

2. Add to CODEOWNERS:
   ```
   /pipelines/domains/{domain}/ @{domain}-team
   /dbt/models/*/{domain}/ @{domain}-team
   /orchestration/workflows/{domain}/ @{domain}-team
   ```

3. Create CI/CD workflow:
   ```bash
   cp .github/workflows/pipelines-trips.yaml .github/workflows/pipelines-{domain}.yaml
   # Update paths and triggers
   ```

4. Add ArgoCD application:
   ```bash
   # In platform/argocd/applications/domain-apps.yaml
   # Add new Application for the domain
   ```

See [docs/runbooks/deploy-new-domain.md](runbooks/deploy-new-domain.md) for detailed steps.
