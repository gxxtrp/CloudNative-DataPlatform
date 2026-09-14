variable "project_id" {
  type        = string
  description = "GCP Project ID."
}

variable "region" {
  type        = string
  description = "Regional location for Artifact Registry."
}

variable "node_service_account_email" {
  type        = string
  description = "Node service account email from foundation stack."
}

variable "bucket_name" {
  type        = string
  description = "Lake bucket name from data-services stack."
}

variable "lake_buckets" {
  type        = map(any)
  default     = {}
  description = "Map of Medallion lake buckets from data-services stack."
}

variable "repository_id" {
  type        = string
  description = "Artifact Registry repository ID from data-services stack."
}

variable "workload_sa_name" {
  type        = string
  description = "Google Service Account ID for workloads."
  default     = "platform-dev-workload"
}

variable "workload_namespace" {
  type        = string
  description = "Default Kubernetes namespace for workload execution."
  default     = "platform"
}

variable "workload_ksa_name" {
  type        = string
  description = "Default Kubernetes Service Account name for Workload Identity."
  default     = "platform-workload"
}

variable "workload_identity_bindings" {
  type = list(object({
    namespace = string
    ksa_name  = string
  }))
  default     = []
  description = "List of Kubernetes ServiceAccounts to bind to Google Service Account."
}
