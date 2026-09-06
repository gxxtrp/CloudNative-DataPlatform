variable "data_path" {
  description = "Dedicated isolated storage path for Longhorn blocks"
  type        = string
  default     = "/data/k3s-storage"
}

variable "replica_count" {
  description = "Number of volume replicas across worker nodes"
  type        = number
  default     = 2
}

variable "chart_version" {
  description = "Longhorn Helm chart version"
  type        = string
  default     = "1.7.0"
}
