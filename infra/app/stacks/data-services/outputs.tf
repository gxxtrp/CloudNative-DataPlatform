output "buckets" {
  value       = module.lake_storage.buckets
  description = "Map of all created Medallion buckets."
}

output "bucket_name" {
  value       = module.lake_storage.bucket_name
  description = "Default/Bronze lake storage bucket name for backward compatibility."
}

output "bucket_url" {
  value       = module.lake_storage.bucket_url
  description = "Default/Bronze lake storage bucket URL for backward compatibility."
}

output "bronze_bucket_name" {
  value       = module.lake_storage.bronze_bucket_name
  description = "Bronze tier bucket name."
}

output "silver_bucket_name" {
  value       = module.lake_storage.silver_bucket_name
  description = "Silver tier bucket name."
}

output "gold_bucket_name" {
  value       = module.lake_storage.gold_bucket_name
  description = "Gold tier bucket name."
}

output "repository_id" {
  value       = module.lake_storage.repository_id
  description = "Artifact Registry repository ID."
}

output "repository_name" {
  value       = module.lake_storage.repository_name
  description = "Artifact Registry repository name."
}
