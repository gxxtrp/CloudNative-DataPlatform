variable "workload_project_id" {
  description = "Existing standalone GCP project ID that owns the publisher network."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.workload_project_id))
    error_message = "workload_project_id must be a valid GCP project ID."
  }
}

variable "region" {
  description = "Single region for Cloud Run, Cloud SQL, and Managed Kafka client access."
  type        = string

  validation {
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]+$", var.region))
    error_message = "region must be a GCP region identifier such as asia-southeast1."
  }
}

variable "environment" {
  description = "Deployment environment label."
  type        = string
  default     = "poc"
}

variable "subnet_cidr" {
  description = "RFC1918 range used by Cloud Run Direct VPC egress and the Managed Kafka PSC endpoints."
  type        = string
  default     = "10.20.0.0/24"
}
