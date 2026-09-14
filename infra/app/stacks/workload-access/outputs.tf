output "workload_service_account_email" {
  value       = google_service_account.workload.email
  description = "Workload Google Service Account email."
}

output "workload_identity_bindings" {
  value       = { for k, b in google_service_account_iam_member.k8s_workload_identity : k => b.id }
  description = "Map of Workload Identity binding IDs."
}

output "workload_identity_binding" {
  value       = values(google_service_account_iam_member.k8s_workload_identity)[0].id
  description = "Default Workload Identity binding ID for backward compatibility."
}

output "lake_storage_grants" {
  value       = { for k, m in google_storage_bucket_iam_member.workload_lake : k => m.id }
  description = "Lake bucket storage grant IDs per tier."
}

output "lake_storage_grant" {
  value       = try(google_storage_bucket_iam_member.workload_lake["bronze"].id, values(google_storage_bucket_iam_member.workload_lake)[0].id)
  description = "Primary lake bucket storage grant ID for backward compatibility."
}

output "node_registry_grant" {
  value       = google_artifact_registry_repository_iam_member.node_registry_reader.id
  description = "Node registry reader grant ID."
}
