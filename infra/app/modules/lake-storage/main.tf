resource "google_storage_bucket" "lake" {
  project                     = var.project_id
  name                        = var.bucket_name
  location                    = var.location
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = false

  versioning {
    enabled = true
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "google_artifact_registry_repository" "images" {
  project       = var.project_id
  location      = var.location
  repository_id = var.repository_id
  description   = "Platform container images (dev)"
  format        = "DOCKER"
}
