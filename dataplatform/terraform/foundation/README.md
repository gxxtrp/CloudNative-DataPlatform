# GCP Foundation Terraform

This module is the Data Platform module's external seam. It owns only Data Platform GCP products, the shared GitHub Workload Identity Pool, and the Data Platform GitHub plan identity.

## One-time bootstrap

1. Verify `gs://dataplatform-508107-tf-state` exists, has versioning, and remains private. It holds only this root's state.
2. Copy `terraform.tfvars.example` to `terraform.tfvars` and enter the Data Platform project ID and number, owner, and approved region. The file is intentionally ignored by Git.
3. Run `terraform init`, then `terraform plan` with an administrator account.
4. Apply this root before the Workload root because it creates the shared GitHub Workload Identity Pool.

No `apply` should occur until the selected region, project IDs, the existing global `billing-cap` alert, and the cross-project Managed Kafka network design are reviewed. A budget alert does not prevent charges or make GKE, Managed Kafka, or Cloud SQL free.

## Ownership

- `dataplatform` owns GKE Autopilot, Managed Kafka, Cloud Storage, BigQuery, Dataform, Secret Manager, platform observability, and the shared GitHub identity pool.
- `workload` owns Cloud Run, Cloud SQL, its independent Terraform state, and a local plan identity for the deliberately small Product publisher modules.

The GitHub `terraform-plan` account has only project viewing plus access to this root's state bucket. It cannot create resources. Resource-creation identities are deferred to later modules after the connectivity spike succeeds.
