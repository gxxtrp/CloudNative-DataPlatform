mock_provider "google" {}
variables {
  project_id  = "test-project"
  bucket_name = "test-project-state"
  location    = "us-central1"
}
run "state_storage_protection" {
  command = plan
  assert {
    condition = (
      google_storage_bucket.state.uniform_bucket_level_access &&
      google_storage_bucket.state.public_access_prevention == "enforced" &&
      google_storage_bucket.state.versioning[0].enabled &&
      !google_storage_bucket.state.force_destroy
    )
    error_message = "State must remain private, versioned and protected against force deletion."
  }
}
