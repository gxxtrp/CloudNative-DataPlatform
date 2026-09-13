output "bucket_name" {
  value       = module.lake_storage.bucket_name
  description = "Lake storage bucket name."
}

output "bucket_url" {
  value       = module.lake_storage.bucket_url
  description = "Lake storage bucket URL."
}

output "repository_id" {
  value       = module.lake_storage.repository_id
  description = "Artifact Registry repository ID."
}

output "repository_name" {
  value       = module.lake_storage.repository_name
  description = "Artifact Registry repository name."
}
