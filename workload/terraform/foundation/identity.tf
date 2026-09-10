locals {
  terraform_plan_service_account_id = "terraform-plan"
  state_bucket_name                 = "${var.workload_project_id}-tf-state"
  github_repository_principal = join("", [
    "principalSet://iam.googleapis.com/projects/",
    var.dataplatform_project_number,
    "/locations/global/workloadIdentityPools/",
    var.github_workload_identity_pool_id,
    "/attribute.repository/",
    var.github_repository,
  ])
}

resource "google_service_account" "terraform_plan" {
  project      = var.workload_project_id
  account_id   = local.terraform_plan_service_account_id
  display_name = "Terraform plan for Workload"
  description  = "Read-only GitHub Actions identity for Terraform plans."

  # The IAM API is enabled by this same root. Do not allow Terraform to race a
  # service-account create against first-time API activation.
  depends_on = [google_project_service.workload["iam.googleapis.com"]]
}

# The pool itself is owned by the Data Platform project. This binding is the
# narrow cross-project seam: only this repository may impersonate this local
# Workload identity.
resource "google_service_account_iam_member" "github_actions_impersonates_plan" {
  service_account_id = google_service_account.terraform_plan.name
  role               = "roles/iam.workloadIdentityUser"
  member             = local.github_repository_principal
}

resource "google_project_iam_member" "terraform_plan_viewer" {
  project = var.workload_project_id
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
