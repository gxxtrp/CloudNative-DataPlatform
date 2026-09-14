variable "project_id" {
  type        = string
  description = "GCP project ID."
}

variable "region" {
  type        = string
  description = "GCP region."
}

variable "repository_id" {
  type        = string
  description = "Artifact Registry repository ID."
}

variable "buckets" {
  type = map(object({
    name                       = string
    storage_class              = optional(string, "STANDARD")
    location                   = optional(string, null)
    versioning                 = optional(bool, true)
    retention_days             = optional(number, null)
    noncurrent_version_days    = optional(number, 7)
    soft_delete_retention_days = optional(number, 0)
    force_destroy              = optional(bool, false)
  }))
  description = "Map of Medallion storage buckets with their configurations."
}
