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
  description = "Kubernetes namespace for workload execution."
  default     = "platform"
}

variable "workload_ksa_name" {
  type        = string
  description = "Kubernetes Service Account name for Workload Identity."
  default     = "platform-workload"
}
