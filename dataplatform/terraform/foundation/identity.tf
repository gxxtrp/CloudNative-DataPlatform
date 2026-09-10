locals {
  terraform_plan_service_account_id = "terraform-plan"
  state_bucket_name                 = "${var.dataplatform_project_id}-tf-state"
}

# This pool is the shared source of GitHub identities. It has no standing
# permissions: each project grants a repository principal access to its own
# local service account.
resource "google_iam_workload_identity_pool" "github_actions" {
  project                   = var.dataplatform_project_id
  workload_identity_pool_id = var.github_workload_identity_pool_id
  display_name              = "GitHub Actions"
  description               = "Short-lived credentials for ${var.github_repository}."
  disabled                  = false

  depends_on = [google_project_service.dataplatform]
}

resource "google_iam_workload_identity_pool_provider" "github_actions" {
  project                            = var.dataplatform_project_id
  workload_identity_pool_id          = google_iam_workload_identity_pool.github_actions.workload_identity_pool_id
  workload_identity_pool_provider_id = var.github_workload_identity_provider_id
  display_name                       = "GitHub Actions OIDC"

  attribute_mapping = {
    "google.subject"          = "assertion.sub"
    "attribute.repository"    = "assertion.repository"
    "attribute.repository_id" = "assertion.repository_id"
    "attribute.ref"           = "assertion.ref"
  }

  # GitHub's issuer is shared. Restrict credentials to this repository and its
  # protected deployment branch rather than trusting the issuer alone.
  attribute_condition = "assertion.repository == '${var.github_repository}' && assertion.ref == 'refs/heads/main'"

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

resource "google_service_account" "terraform_plan" {
  project      = var.dataplatform_project_id
  account_id   = local.terraform_plan_service_account_id
  display_name = "Terraform plan for Data Platform"
  description  = "Read-only GitHub Actions identity for Terraform plans."

  # The IAM API is enabled by this same root. Do not allow Terraform to race a
  # service-account create against first-time API activation.
  depends_on = [google_project_service.dataplatform["iam.googleapis.com"]]
}

resource "google_service_account_iam_member" "github_actions_impersonates_plan" {
  service_account_id = google_service_account.terraform_plan.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github_actions.name}/attribute.repository/${var.github_repository}"
}

# The CI identity can inspect this project and read/write only this root's
# remote state. It deliberately has no resource-creation roles.
resource "google_project_iam_member" "terraform_plan_viewer" {
  project = var.dataplatform_project_id
  role    = "roles/viewer"
  member  = "serviceAccount:${google_service_account.terraform_plan.email}"
}

resource "google_storage_bucket_iam_member" "terraform_plan_state_metadata" {
  bucket = local.state_bucket_name
  role   = "roles/storage.bucketViewer"
  member = "serviceAccount:${google_service_account.terraform_plan.email}"
}

resource "google_storage_bucket_iam_member" "terraform_plan_state_objects" {
  bucket = local.state_bucket_name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.terraform_plan.email}"
}

output "github_workload_identity_provider" {
  description = "GitHub Actions OIDC provider resource name. Configure this as a GitHub repository variable after apply."
  value       = google_iam_workload_identity_pool_provider.github_actions.name
}

output "terraform_plan_service_account" {
  description = "Plan-only service account that GitHub Actions may impersonate."
  value       = google_service_account.terraform_plan.email
}
