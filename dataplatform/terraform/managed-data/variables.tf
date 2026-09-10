variable "dataplatform_project_id" {
  description = "Existing standalone GCP project ID that owns managed data resources."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.dataplatform_project_id))
    error_message = "dataplatform_project_id must be a valid GCP project ID."
  }
}

variable "region" {
  description = "Single GCP region for data residency; Singapore is asia-southeast1."
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

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,62}$", var.environment))
    error_message = "environment must be a lowercase label value."
  }
}

variable "raw_retention_days" {
  description = "Number of days to retain synthetic raw event objects."
  type        = number
  default     = 90

  validation {
    condition     = var.raw_retention_days >= 1
    error_message = "raw_retention_days must be at least one day."
  }
}

variable "quarantine_retention_days" {
  description = "Number of days to retain invalid-event evidence."
  type        = number
  default     = 30

  validation {
    condition     = var.quarantine_retention_days >= 1
    error_message = "quarantine_retention_days must be at least one day."
  }
}

variable "transient_retention_days" {
  description = "Number of days to retain processor checkpoints and build artifacts."
  type        = number
  default     = 14

  validation {
    condition     = var.transient_retention_days >= 1
    error_message = "transient_retention_days must be at least one day."
  }
}
