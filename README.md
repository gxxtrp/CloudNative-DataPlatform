# Delivery Data Platform on GCP

A portfolio implementation of a production-oriented delivery data platform. The repository focuses on the platform seam: immutable event contracts, private Google Cloud foundations, a managed data plane, and a small pair of publisher modules.

## Current foundation

```text
workload-508107
  Cloud Run publishers + Cloud SQL transactional outbox + private VPC
  └── private, cross-project event publication

dataplatform-508107
  Managed Kafka → planned GKE Autopilot processing modules → Cloud Storage / BigQuery
  Argo CD, Argo Workflows, and Flink are planned as self-managed GKE modules.
```

Terraform state is deliberately separated:

| Terraform root | State location | Ownership |
| --- | --- | --- |
| `dataplatform/terraform/foundation` | `gs://dataplatform-508107-tf-state/foundation` | GCP data-platform foundation and shared GitHub identity pool |
| `dataplatform/terraform/managed-data` | `gs://dataplatform-508107-tf-state/managed-data` | Storage zones and BigQuery datasets |
| `dataplatform/terraform/managed-kafka` | `gs://dataplatform-508107-tf-state/managed-kafka` | Managed Kafka, topic ACLs, cross-project client subnet permission |
| `workload/terraform/foundation` | `gs://workload-508107-tf-state/foundation` | Publisher foundation and its local GitHub plan identity |
| `workload/terraform/network` | `gs://workload-508107-tf-state/network` | Private VPC and Cloud Run subnet |
| `workload/terraform/cloud-sql` | `gs://workload-508107-tf-state/cloud-sql` | Private Cloud SQL and publisher identities |
| `workload/terraform/artifact-registry` | `gs://workload-508107-tf-state/artifact-registry` | Private container registry |
| `workload/terraform/cloud-run` | `gs://workload-508107-tf-state/cloud-run` | Internal-only publisher deployments |

GitHub Actions can run manual Terraform plans using OIDC and short-lived, plan-only GCP identities. It cannot apply infrastructure.

## Repository layout

```text
contracts/                 # Versioned producer contracts and compatibility checks
workload/
  apps/                     # Order and Rider publisher modules
  terraform/                # Foundation, VPC, Cloud SQL, registry, Cloud Run roots
dataplatform/
  terraform/                # Foundation, managed data, and Managed Kafka roots
docs/
  governance/               # Processing invariants
  infra/                    # GCP migration plan
  setup/                    # Terraform and GitHub OIDC setup
```

## Local verification

```sh
make test-contracts
make test
make terraform-validate
```

For environment setup and GitHub repository variables, see [GCP foundation and GitHub OIDC setup](docs/setup/gcp-github-oidc.md). The planned end-state and migration phases are in [the GCP refactor plan](docs/infra/gcp-refactor-plan.md).

## Local Terraform configuration

Each Terraform root commits a `terraform.tfvars.example` file. Copy or maintain its matching `terraform.tfvars` only on the machine that performs an apply; these local files are deliberately ignored so project IDs, operator identity, and generated runtime values never become tracked configuration. GitHub Actions uses repository variables and OIDC for plans only.

## Phase 5 deployment order

Apply one Terraform root at a time; do not use a repository-wide apply. Set `terraform_operator_email` in `workload/terraform/cloud-sql/terraform.tfvars` to the same Google account that has ADC. The other manual values are the two container image digests and the Managed Kafka bootstrap address, which become available only after the preceding roots exist.

1. Re-apply both `foundation` roots to enable Cloud Build and Private Service Access.
2. Apply `workload/terraform/network`, then `workload/terraform/cloud-sql`.
3. Apply `dataplatform/terraform/managed-data`, then `dataplatform/terraform/managed-kafka`. Managed Kafka is continuously billable; inspect its plan before applying.
4. Apply `workload/terraform/artifact-registry`, build and push the two publisher images, then set the digest-qualified image references and Kafka bootstrap address in `workload/terraform/cloud-run/terraform.tfvars`.
5. Apply `workload/terraform/cloud-run` and use the Cloud Run internal ingress path from the same private VPC for the synthetic demonstration.

The Order and Rider modules expose a narrow deep interface: an HTTP action is committed with an outbox row in one Cloud SQL transaction, then relayed to Managed Kafka using the Cloud Run service account's short-lived access token. This is at-least-once transport with a stable UUID `event_id`; the future intake module must deduplicate by that field.
