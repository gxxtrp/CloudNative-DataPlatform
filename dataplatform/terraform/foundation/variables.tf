variable "dataplatform_project_id" {
  description = "Existing standalone GCP project ID that owns the Data Platform."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.dataplatform_project_id))
    error_message = "dataplatform_project_id must be a valid GCP project ID."
  }
}

variable "dataplatform_project_number" {
  description = "Immutable project number for the Data Platform project."
  type        = string

  validation {
    condition     = can(regex("^[0-9]+$", var.dataplatform_project_number))
    error_message = "dataplatform_project_number must contain only digits."
  }
}

variable "region" {
  description = "GCP region selected after confirming Managed Kafka, GKE, and Cloud SQL availability."
  type        = string

  validation {
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]+$", var.region))
    error_message = "region must be a GCP region identifier such as asia-southeast1."
  }
}

variable "platform_owner_email" {
  description = "Human GCP owner for the POC. Never commit this value."
  type        = string
  sensitive   = true
}

variable "github_repository" {
  description = "GitHub repository permitted to exchange OIDC tokens for plan-only identities."
  type        = string
  default     = "gxxtrp/CloudNative-DataPlatform"

  validation {
    condition     = can(regex("^[^/]+/[^/]+$", var.github_repository))
    error_message = "github_repository must have the form owner/repository."
  }
}

variable "github_workload_identity_pool_id" {
  description = "Stable ID for the shared GitHub Actions Workload Identity Pool."
  type        = string
  default     = "github-actions"
}

variable "github_workload_identity_provider_id" {
  description = "Stable ID for the GitHub Actions OIDC provider."
  type        = string
  default     = "github"
}

variable "private_connectivity_only" {
  description = "When true, future network modules must not create public data-plane endpoints."
  type        = bool
  default     = true
}

variable "synthetic_data_only" {
  description = "Whether the POC must contain only generated data."
  type        = bool
  default     = true
}
