# BigQuery Stack Variables

variable "project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "env" {
  description = "Environment (dev, staging, prod)"
  type        = string
}

variable "bigquery_location" {
  description = "BigQuery dataset location"
  type        = string
  default     = "US"
}

variable "bigquery_datasets" {
  description = "List of BigQuery datasets to create"
  type        = list(string)
  default     = ["bronze", "silver", "gold"]
}
