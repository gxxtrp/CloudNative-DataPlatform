resource "google_compute_network" "workload" {
  project                         = var.workload_project_id
  name                            = "workload-private"
  auto_create_subnetworks         = false
  delete_default_routes_on_create = false
  routing_mode                    = "REGIONAL"
}

# Cloud Run uses Direct VPC egress from this subnet. Private Google Access lets
# internal-only Cloud Run callers reach Google control-plane endpoints without
# adding a public IP or a Cloud NAT gateway.
resource "google_compute_subnetwork" "cloud_run" {
  project                  = var.workload_project_id
  name                     = "workload-run"
  region                   = var.region
  network                  = google_compute_network.workload.id
  ip_cidr_range            = var.subnet_cidr
  private_ip_google_access = true

  log_config {
    aggregation_interval = "INTERVAL_5_SEC"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}
