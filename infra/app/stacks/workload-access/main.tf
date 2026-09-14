resource "google_service_account" "workload" {
  project      = var.project_id
  account_id   = var.workload_sa_name
  display_name = "Data platform workload identity (dev)"
}

# Grant objectUser across all Medallion tiers
resource "google_storage_bucket_iam_member" "workload_lake" {
  for_each = var.lake_buckets != null && length(var.lake_buckets) > 0 ? var.lake_buckets : { default = { name = var.bucket_name } }
  bucket   = each.value.name
  role     = "roles/storage.objectUser"
  member   = "serviceAccount:${google_service_account.workload.email}"
}

resource "google_service_account_iam_member" "k8s_workload_identity" {
  service_account_id = google_service_account.workload.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[${var.workload_namespace}/${var.workload_ksa_name}]"
}

resource "google_artifact_registry_repository_iam_member" "node_registry_reader" {
  project    = var.project_id
  location   = var.region
  repository = var.repository_id
  role       = "roles/artifactregistry.reader"
  member     = "serviceAccount:${var.node_service_account_email}"
}
