output "cluster_id" {
  value       = module.gke.cluster_id
  description = "Cluster ID."
}

output "cluster_name" {
  value       = module.gke.cluster_name
  description = "Cluster name."
}

output "endpoint" {
  value       = module.gke.endpoint
  description = "Cluster control plane endpoint."
}

output "ca_certificate" {
  value       = module.gke.ca_certificate
  description = "Cluster CA certificate."
  sensitive   = true
}

output "workload_identity_pool" {
  value       = module.gke.workload_identity_pool
  description = "Workload Identity pool."
}

output "core_node_pool_id" {
  value       = module.gke.core_node_pool_id
  description = "Core node pool ID."
}

output "compute_node_pool_id" {
  value       = module.gke.compute_node_pool_id
  description = "Compute node pool ID."
}
