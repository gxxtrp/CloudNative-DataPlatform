mock_provider "google" {}

variables {
  project_id          = "test-project"
  region              = "us-central1"
  node_cidr           = "10.80.0.0/22"
  pod_cidr            = "10.84.0.0/18"
  service_cidr        = "10.88.0.0/22"
  deployment_reviewed = true
}

run "node_identity_boundary" {
  command = plan
  assert {
    condition     = google_project_iam_member.nodes.role == "roles/container.defaultNodeServiceAccount"
    error_message = "Node identity must have only its node infrastructure role."
  }
  assert {
    condition     = alltrue([for api in google_project_service.required : !api.disable_on_destroy])
    error_message = "Removing this stack must not disable project APIs."
  }
}

run "require_deployment_review" {
  command = plan
  variables {
    deployment_reviewed = false
  }
  expect_failures = [var.deployment_reviewed]
}
