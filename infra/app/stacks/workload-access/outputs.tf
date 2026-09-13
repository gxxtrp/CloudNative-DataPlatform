output "workload_service_account_email" {
  value       = google_service_account.workload.email
  description = "Workload Google Service Account email."
}

output "workload_identity_binding" {
  value       = google_service_account_iam_member.k8s_workload_identity.id
  description = "Workload Identity binding ID."
}

output "lake_storage_grant" {
  value       = google_storage_bucket_iam_member.workload_lake.id
  description = "Lake bucket storage grant ID."
}

output "node_registry_grant" {
  value       = google_artifact_registry_repository_iam_member.node_registry_reader.id
  description = "Node registry reader grant ID."
}
