mock_provider "google" {}

variables {
  project_id                 = "test-project"
  region                     = "asia-southeast1"
  name                       = "platform-test-gke"
  network_id                 = "projects/test-project/global/networks/test-vpc"
  subnetwork_id              = "projects/test-project/regions/asia-southeast1/subnetworks/test-subnet"
  pod_range_name             = "pods"
  service_range_name         = "services"
  node_service_account_email = "node-sa@test-project.iam.gserviceaccount.com"
}

run "cluster_stack_contract" {
  command = plan

  assert {
    condition     = module.gke.cluster_name == "platform-test-gke"
    error_message = "Cluster stack must pass name to GKE module."
  }

  assert {
    condition     = module.gke.workload_identity_pool == "test-project.svc.id.goog"
    error_message = "Cluster stack must export correct Workload Identity pool."
  }
}
