output "bucket_name" {
  value       = google_storage_bucket.lake.name
  description = "Lake storage bucket name."
}

output "bucket_url" {
  value       = google_storage_bucket.lake.url
  description = "Lake storage bucket URL."
}

output "repository_id" {
  value       = google_artifact_registry_repository.images.repository_id
  description = "Artifact Registry repository ID."
}

output "repository_name" {
  value       = google_artifact_registry_repository.images.name
  description = "Artifact Registry repository resource name."
}
