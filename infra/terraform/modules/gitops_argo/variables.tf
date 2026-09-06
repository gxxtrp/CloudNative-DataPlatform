variable "argocd_chart_version" {
  description = "ArgoCD Helm chart version"
  type        = string
  default     = "6.7.0"
}

variable "argo_workflows_chart_version" {
  description = "Argo Workflows Helm chart version"
  type        = string
  default     = "0.41.0"
}
