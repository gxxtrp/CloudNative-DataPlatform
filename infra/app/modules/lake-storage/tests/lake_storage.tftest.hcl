mock_provider "google" {}

variables {
  project_id    = "test-project"
  location      = "asia-southeast1"
  bucket_name   = "test-lake-bucket"
  repository_id = "test-images"
}

run "lake_storage_contract" {
  command = plan

  assert {
    condition     = google_storage_bucket.lake.uniform_bucket_level_access
    error_message = "Lake bucket must have uniform bucket level access enabled."
  }

  assert {
    condition     = google_storage_bucket.lake.public_access_prevention == "enforced"
    error_message = "Lake bucket must enforce public access prevention."
  }

  assert {
    condition     = google_storage_bucket.lake.versioning[0].enabled
    error_message = "Lake bucket must have versioning enabled."
  }

  assert {
    condition     = google_artifact_registry_repository.images.format == "DOCKER"
    error_message = "Artifact Registry must be configured for DOCKER format."
  }
}
