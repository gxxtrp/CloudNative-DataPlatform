output "storage_class_name" {
  description = "Default isolated Longhorn storageclass name"
  value       = kubernetes_storage_class.longhorn_isolated.metadata[0].name
}

output "longhorn_ui_nodeport" {
  description = "NodePort on which Longhorn UI is exposed"
  value       = "30088"
}
