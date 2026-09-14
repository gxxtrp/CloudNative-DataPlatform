output "buckets" {
  value = {
    for k, b in google_storage_bucket.tiers : k => {
      name      = b.name
      url       = b.url
      self_link = b.self_link
      location  = b.location
    }
  }
  description = "Map of all created Medallion buckets."
}

output "bucket_name" {
  value       = contains(keys(google_storage_bucket.tiers), "bronze") ? google_storage_bucket.tiers["bronze"].name : values(google_storage_bucket.tiers)[0].name
  description = "Primary / Bronze lake storage bucket name for backward compatibility."
}

output "bucket_url" {
  value       = contains(keys(google_storage_bucket.tiers), "bronze") ? google_storage_bucket.tiers["bronze"].url : values(google_storage_bucket.tiers)[0].url
  description = "Primary / Bronze lake storage bucket URL for backward compatibility."
}

output "bronze_bucket_name" {
  value       = try(google_storage_bucket.tiers["bronze"].name, null)
  description = "Bronze tier bucket name."
}

output "silver_bucket_name" {
  value       = try(google_storage_bucket.tiers["silver"].name, null)
  description = "Silver tier bucket name."
}

output "gold_bucket_name" {
  value       = try(google_storage_bucket.tiers["gold"].name, null)
  description = "Gold tier bucket name."
}

output "repository_id" {
  value       = google_artifact_registry_repository.images.repository_id
  description = "Artifact Registry repository ID."
}

output "repository_name" {
  value       = google_artifact_registry_repository.images.name
  description = "Artifact Registry repository resource name."
}
