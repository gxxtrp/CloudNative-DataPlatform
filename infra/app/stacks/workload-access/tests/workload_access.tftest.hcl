mock_provider "google" {}

variables {
  project_id                 = "test-project"
  region                     = "asia-southeast1"
  node_service_account_email = "node-sa@test-project.iam.gserviceaccount.com"
  bucket_name                = "test-lake-bucket"
  repository_id              = "test-images"
  workload_sa_name           = "platform-test-workload"
  workload_namespace         = "platform"
  workload_ksa_name          = "platform-workload"
}

run "workload_access_contract" {
  command = plan

  assert {
    condition     = google_storage_bucket_iam_member.workload_lake.role == "roles/storage.objectUser"
    error_message = "Workload SA must have objectUser on lake bucket."
  }

  assert {
    condition     = google_artifact_registry_repository_iam_member.node_registry_reader.role == "roles/artifactregistry.reader"
    error_message = "Node SA must have reader on Artifact Registry."
  }

  assert {
    condition     = google_service_account_iam_member.k8s_workload_identity.role == "roles/iam.workloadIdentityUser"
    error_message = "K8s SA must be bound to Google SA with workloadIdentityUser role."
  }
}
