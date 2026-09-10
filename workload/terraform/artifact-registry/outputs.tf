output "repository_url" {
  description = "OCI repository prefix used to publish the Order and Rider images."
  value       = "${var.region}-docker.pkg.dev/${var.workload_project_id}/${google_artifact_registry_repository.publishers.repository_id}"
}
