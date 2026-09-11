# Storage Stack - GCS buckets for data lake

# Main data lake bucket
resource "google_storage_bucket" "lake" {
  name     = var.lake_bucket_name
  project  = var.project_id
  location = var.lake_location

  # Prevent accidental deletion in production
  force_destroy = var.env != "prod"

  uniform_bucket_level_access = true

  versioning {
    enabled = true
  }

  # Lifecycle rules
  lifecycle_rule {
    condition {
      age = 90
      matches_prefix = ["bronze/"]
    }
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
  }

  lifecycle_rule {
    condition {
      age = 365
      matches_prefix = ["bronze/"]
    }
    action {
      type          = "SetStorageClass"
      storage_class = "COLDLINE"
    }
  }

  labels = {
    env     = var.env
    purpose = "data-lake"
  }
}

# Create folder structure (empty objects as markers)
resource "google_storage_bucket_object" "lake_structure" {
  for_each = toset([
    "bronze/.keep",
    "silver/.keep",
    "gold/.keep",
    "checkpoints/.keep",
    "temp/.keep"
  ])

  name    = each.value
  content = ""
  bucket  = google_storage_bucket.lake.name
}

# Artifact bucket for Spark/Flink JARs
resource "google_storage_bucket" "artifacts" {
  name     = "${var.project_id}-artifacts"
  project  = var.project_id
  location = var.lake_location

  force_destroy = var.env != "prod"
  uniform_bucket_level_access = true

  labels = {
    env     = var.env
    purpose = "artifacts"
  }
}

# Outputs
output "lake_bucket_name" {
  value = google_storage_bucket.lake.name
}

output "lake_bucket_url" {
  value = google_storage_bucket.lake.url
}

output "artifacts_bucket_name" {
  value = google_storage_bucket.artifacts.name
}
