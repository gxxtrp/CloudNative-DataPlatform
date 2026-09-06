variable "namespaces" {
  description = "Namespaces to create in the cluster"
  type        = list(string)
  default = [
    "platform",
    "apps",
    "observability",
    "argocd",
    "argo-workflow",
    "longhorn-system",
  ]
}

variable "environment" {
  description = "Environment identifier (self_manage or free_tier_aws)"
  type        = string
  default     = "self_manage"
}
