output "workload_project_id" {
  description = "Project ID that owns Product publisher resources."
  value       = var.workload_project_id
}

output "enabled_workload_products" {
  description = "GCP products enabled in the Workload project."
  value       = sort(tolist(local.workload_products))
}

output "terraform_plan_service_account" {
  description = "Plan-only service account that GitHub Actions may impersonate."
  value       = google_service_account.terraform_plan.email
}

output "platform_context" {
  description = "Non-sensitive constraints that later Terraform modules must preserve."
  value = {
    private_connectivity_only = var.private_connectivity_only
    region                    = var.region
    synthetic_data_only       = var.synthetic_data_only
  }
}
