mock_provider "google" {}

variables {
  project_id                 = "test-project"
  region                     = "asia-southeast1"
  name                       = "platform-test"
  network_id                 = "projects/test-project/global/networks/test-vpc"
  subnetwork_id              = "projects/test-project/regions/asia-southeast1/subnetworks/test-subnet"
  pod_range_name             = "pods"
  service_range_name         = "services"
  node_service_account_email = "node-sa@test-project.iam.gserviceaccount.com"
}

run "gke_configuration_contract" {
  command = plan

  assert {
    condition     = google_container_cluster.primary.private_cluster_config[0].enable_private_nodes
    error_message = "GKE nodes must be private with no external IP addresses."
  }

  assert {
    condition     = google_container_cluster.primary.datapath_provider == "ADVANCED_DATAPATH"
    error_message = "Cluster must use Dataplane V2."
  }

  assert {
    condition     = google_container_cluster.primary.workload_identity_config[0].workload_pool == "test-project.svc.id.goog"
    error_message = "Workload Identity must be configured with the project pool."
  }

  assert {
    condition     = google_container_node_pool.core.autoscaling[0].min_node_count == 1
    error_message = "Core pool minimum node count must be 1."
  }

  assert {
    condition     = google_container_node_pool.compute.autoscaling[0].min_node_count == 0
    error_message = "Compute pool minimum node count must be 0 (scale-to-zero)."
  }

  assert {
    condition     = length(google_container_node_pool.compute.node_config[0].taint) == 1 && google_container_node_pool.compute.node_config[0].taint[0].key == "workload" && google_container_node_pool.compute.node_config[0].taint[0].effect == "NO_SCHEDULE"
    error_message = "Compute pool must have dedicated workload=compute:NoSchedule taint."
  }
}
