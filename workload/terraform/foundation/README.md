# Workload GCP Foundation Terraform

This module is the Workload module's external seam. It creates only the Workload project's enabled products and GitHub plan identity. Its remote state is permanently isolated in `gs://workload-508107-tf-state/foundation`.

The shared GitHub Workload Identity Pool is owned by the Data Platform project. The sole cross-project reference here is a repository-scoped impersonation binding for the local `terraform-plan` service account.

## First local plan

1. Copy `terraform.tfvars.example` to ignored `terraform.tfvars` and fill in the verified project numbers.
2. Run `terraform init` to use the pre-created Workload state bucket.
3. Run `terraform plan` with an administrator account. The first apply creates the plan-only identity.

Do not add resource-creation roles to `terraform-plan`. Future apply identities must be defined per Terraform module and scoped to the resources that module owns.
