# GCP foundation and GitHub OIDC setup

The repository uses two Terraform roots and two remote-state buckets:

| Root | State location | Owns |
| --- | --- | --- |
| `dataplatform/terraform/foundation` | `gs://dataplatform-508107-tf-state/foundation` | Data Platform products and the shared GitHub Workload Identity Pool |
| `workload/terraform/foundation` | `gs://workload-508107-tf-state/foundation` | Workload products and its local GitHub plan identity |

The only cross-project seam is an impersonation binding: the Workload plan identity trusts the repository principal from the Workload Identity Pool in the Data Platform project. No state bucket, deploy identity, or runtime resource is shared.

## Your required actions

1. Check that `thxxrxpxt.x@gmail.com` remains a Project Owner and Billing Account Administrator while bootstrapping. The plan identities intentionally cannot apply resource changes.
2. Create local Application Default Credentials (ADC). `gcloud auth login` alone is not enough for Terraform's GCS backend:

   ```sh
   gcloud auth application-default login
   ```

   Complete the browser sign-in with `thxxrxpxt.x@gmail.com`. This writes a local user credential; it does not create a service-account key or change GCP resources.
3. From your own terminal, run these commands in order. Review each plan before any apply:

   ```sh
   cd /Users/admin/Work/TEMP/CloudNative-DataPlatform/dataplatform/terraform/foundation
   terraform init -reconfigure
   terraform plan
   terraform apply

   cd /Users/admin/Work/TEMP/CloudNative-DataPlatform/workload/terraform/foundation
   terraform init -reconfigure
   terraform plan
   terraform apply
   ```

4. The billing-account-wide `billing-cap` remains the sole cost alert. It notifies; it does not cap spend.
5. In GitHub repository **Settings → Secrets and variables → Actions → Variables**, add the following repository variables. They are configuration values, not credentials.

| Variable | Value |
| --- | --- |
| `GCP_DATAPLATFORM_PROJECT_ID` | `dataplatform-508107` |
| `GCP_DATAPLATFORM_PROJECT_NUMBER` | `280898793734` |
| `GCP_WORKLOAD_PROJECT_ID` | `workload-508107` |
| `GCP_WORKLOAD_PROJECT_NUMBER` | `650380149829` |
| `GCP_REGION` | `asia-southeast1` |
| `GCP_PLATFORM_OWNER_EMAIL` | your owner email |
| `GCP_DATAPLATFORM_WIF_PROVIDER` | `terraform output -raw github_workload_identity_provider` from the Data Platform root |
| `GCP_WORKLOAD_WIF_PROVIDER` | same value as `GCP_DATAPLATFORM_WIF_PROVIDER` |
| `GCP_DATAPLATFORM_TERRAFORM_PLAN_SA` | `terraform output -raw terraform_plan_service_account` from the Data Platform root |
| `GCP_WORKLOAD_TERRAFORM_PLAN_SA` | `terraform output -raw terraform_plan_service_account` from the Workload root |

6. From the `main` branch, run **Plan: GCP Terraform** manually in GitHub Actions for each target. The OIDC condition refuses all repositories and branches other than `gxxtrp/CloudNative-DataPlatform` on `main`.

## What this does not do

- It does not grant GitHub permission to apply infrastructure.
- It does not create GKE, Managed Kafka, Cloud SQL, or application data resources.
- It does not create service-account keys. GitHub exchanges its OIDC token for a short-lived credential.
