mock_provider "google" {}

variables {
  project_id   = "test-project"
  region       = "us-central1"
  name         = "platform-test"
  node_cidr    = "10.80.0.0/22"
  pod_cidr     = "10.84.0.0/18"
  service_cidr = "10.88.0.0/22"
}

run "private_network_contract" {
  command = plan
  assert {
    condition     = !google_compute_network.this.auto_create_subnetworks
    error_message = "The network must not create implicit regional subnets."
  }
  assert {
    condition     = google_compute_subnetwork.gke.private_ip_google_access
    error_message = "Private nodes need Private Google Access."
  }
  assert {
    condition     = google_compute_router_nat.this.source_subnetwork_ip_ranges_to_nat == "LIST_OF_SUBNETWORKS"
    error_message = "NAT must be scoped to the GKE subnet."
  }
  assert {
    condition     = length(google_compute_subnetwork.gke.secondary_ip_range) == 2
    error_message = "Pods and Services need distinct named ranges."
  }
}

run "reject_invalid_ipv4_range" {
  command = plan
  variables {
    node_cidr = "not-a-cidr"
  }
  expect_failures = [var.node_cidr]
}
