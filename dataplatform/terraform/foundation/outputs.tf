output "dataplatform_project_id" {
  description = "Project ID that owns Data Platform resources."
  value       = var.dataplatform_project_id
}

output "enabled_dataplatform_products" {
  description = "GCP products enabled in the Data Platform project."
  value       = sort(tolist(local.dataplatform_products))
}

output "platform_context" {
  description = "Non-sensitive constraints that later Terraform modules must preserve."
  value       = local.platform_context
}
