output "namespaces" {
  description = "Created platform namespaces"
  value       = module.k8s_base.created_namespaces
}

output "storage_class" {
  description = "Default Longhorn storage class"
  value       = module.storage_longhorn.storage_class_name
}

output "ui_endpoints" {
  description = "Web UI endpoints"
  value = {
    kong_gateway   = "http://localhost:30000/api/v1"
    argocd         = "http://localhost:30080"
    argo_workflows = "http://localhost:32746"
    longhorn       = "http://localhost:30088"
    flink          = "http://localhost:38081"
    grafana        = "http://localhost:3000"
  }
}
