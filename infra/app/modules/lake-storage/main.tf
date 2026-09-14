resource "google_storage_bucket" "tiers" {
  for_each                    = var.buckets
  project                     = var.project_id
  name                        = each.value.name
  location                    = coalesce(each.value.location, var.location)
  storage_class               = coalesce(each.value.storage_class, "STANDARD")
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = coalesce(each.value.force_destroy, false)

  versioning {
    enabled = coalesce(each.value.versioning, true)
  }

  # Lifecycle: Abort incomplete multipart uploads after 1 day to prevent orphan upload costs
  lifecycle_rule {
    action {
      type = "AbortIncompleteMultipartUpload"
    }
    condition {
      age = 1
    }
  }

  # Lifecycle: Expire non-current object versions after N days to prevent runaway version storage fees
  dynamic "lifecycle_rule" {
    for_each = each.value.noncurrent_version_days != null ? [each.value.noncurrent_version_days] : []
    content {
      action {
        type = "Delete"
      }
      condition {
        days_since_noncurrent_time = lifecycle_rule.value
      }
    }
  }

  # Lifecycle: Optional auto-expiration for transient landing / raw staging data
  dynamic "lifecycle_rule" {
    for_each = each.value.retention_days != null ? [each.value.retention_days] : []
    content {
      action {
        type = "Delete"
      }
      condition {
        age = lifecycle_rule.value
      }
    }
  }

  dynamic "soft_delete_policy" {
    for_each = each.value.soft_delete_retention_days != null ? [each.value.soft_delete_retention_days] : []
    content {
      retention_duration_seconds = soft_delete_policy.value * 86400
    }
  }
}

resource "google_artifact_registry_repository" "images" {
  project       = var.project_id
  location      = var.location
  repository_id = var.repository_id
  description   = "Platform container images (dev)"
  format        = "DOCKER"
}
