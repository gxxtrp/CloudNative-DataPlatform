output "argocd_ui_nodeport" {
  description = "NodePort on which ArgoCD UI is exposed"
  value       = "30080"
}

output "argo_workflows_ui_nodeport" {
  description = "NodePort on which Argo Workflows UI is exposed"
  value       = "32746"
}
