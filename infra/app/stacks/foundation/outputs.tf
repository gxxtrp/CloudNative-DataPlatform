output "project_id" {
  value      = var.project_id
  depends_on = [google_project_service.required]
}
output "network_id" {
  value = module.network.network_id
}
output "subnetwork_id" {
  value = module.network.subnetwork_id
}
output "pod_range_name" {
  value = module.network.pod_range_name
}
output "service_range_name" {
  value = module.network.service_range_name
}
output "node_service_account_email" {
  value      = google_service_account.nodes.email
  depends_on = [google_project_iam_member.nodes]
}
