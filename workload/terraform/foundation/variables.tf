variable "workload_project_id" {
  description = "Existing standalone GCP project ID that owns Product publisher modules."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.workload_project_id))
    error_message = "workload_project_id must be a valid GCP project ID."
  }
}

variable "workload_project_number" {
  description = "Immutable project number for the Workload project."
  type        = string

  validation {
    condition     = can(regex("^[0-9]+$", var.workload_project_number))
    error_message = "workload_project_number must contain only digits."
  }
}

variable "dataplatform_project_number" {
  description = "Project number that owns the shared GitHub Workload Identity Pool."
  type        = string

  validation {
    condition     = can(regex("^[0-9]+$", var.dataplatform_project_number))
    error_message = "dataplatform_project_number must contain only digits."
  }
}

variable "region" {
  description = "GCP region selected for the private-only POC."
  type        = string

  validation {
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]+$", var.region))
    error_message = "region must be a GCP region identifier such as asia-southeast1."
  }
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
