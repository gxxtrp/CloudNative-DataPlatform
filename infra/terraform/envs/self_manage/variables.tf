variable "kubeconfig_path" {
  description = "Path to k3s kubeconfig file"
  type        = string
  default     = "~/.kube/config"
}
