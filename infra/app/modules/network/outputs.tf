output "network_id" {
  value = google_compute_network.this.id
}
output "subnetwork_id" {
  value = google_compute_subnetwork.gke.id
}
output "pod_range_name" {
  value = "pods"
}
output "service_range_name" {
  value = "services"
}
