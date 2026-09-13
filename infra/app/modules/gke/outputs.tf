output "cluster_id" {
  value       = google_container_cluster.primary.id
  description = "Cluster ID."
}

output "cluster_name" {
  value       = google_container_cluster.primary.name
  description = "Cluster name."
}

output "endpoint" {
  value       = google_container_cluster.primary.endpoint
  description = "Cluster control plane endpoint."
}

output "ca_certificate" {
  value       = try(google_container_cluster.primary.master_auth[0].cluster_ca_certificate, "")
  description = "Cluster CA certificate (base64 encoded)."
  sensitive   = true
}

output "workload_identity_pool" {
  value       = "${var.project_id}.svc.id.goog"
  description = "Workload Identity Pool name."
}

output "core_node_pool_id" {
  value       = google_container_node_pool.core.id
  description = "Core node pool ID."
}

output "compute_node_pool_id" {
  value       = google_container_node_pool.compute.id
  description = "Compute node pool ID."
}
