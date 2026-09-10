variable "workload_project_id" {
  description = "Project that owns the private publisher modules."
  type        = string
}

variable "region" {
  description = "Region for the two Cloud Run modules."
  type        = string
}

variable "network_name" {
  description = "Pre-existing Workload VPC name."
  type        = string
  default     = "workload-private"
}

variable "subnetwork_name" {
  description = "Pre-existing subnet used for Direct VPC egress."
  type        = string
  default     = "workload-run"
}

variable "order_image" {
  description = "Immutable Artifact Registry reference for the Order publisher image."
  type        = string
}

variable "rider_image" {
  description = "Immutable Artifact Registry reference for the Rider publisher image."
  type        = string
}

variable "kafka_bootstrap_servers" {
  description = "Private Managed Kafka bootstrap endpoint obtained after the Kafka cluster is active."
  type        = string
}

variable "deletion_protection" {
  description = "Prevent accidental removal of deployed publisher modules."
  type        = bool
  default     = true
}
