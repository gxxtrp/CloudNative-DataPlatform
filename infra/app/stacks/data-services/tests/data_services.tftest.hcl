mock_provider "google" {}

variables {
  project_id    = "test-project"
  region        = "asia-southeast1"
  bucket_name   = "test-lake-bucket"
  repository_id = "test-images"
}

run "data_services_stack_contract" {
  command = plan

  assert {
    condition     = module.lake_storage.bucket_name == "test-lake-bucket"
    error_message = "Data services stack must pass bucket name."
  }

  assert {
    condition     = module.lake_storage.repository_id == "test-images"
    error_message = "Data services stack must pass repository id."
  }
}
