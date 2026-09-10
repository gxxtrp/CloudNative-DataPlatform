output "network_id" {
  description = "Workload VPC self link used by private Cloud SQL."
  value       = google_compute_network.workload.id
}

output "cloud_run_subnet_id" {
  description = "Workload subnet attached to Cloud Run and the cross-project Kafka cluster."
  value       = google_compute_subnetwork.cloud_run.id
}
