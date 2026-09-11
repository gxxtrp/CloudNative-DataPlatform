# Storage Stack Variables

variable "project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "env" {
  description = "Environment (dev, staging, prod)"
  type        = string
}

variable "lake_bucket_name" {
  description = "Name of the data lake bucket"
  type        = string
}

variable "lake_location" {
  description = "Location for the data lake bucket"
  type        = string
  default     = "US"
}
