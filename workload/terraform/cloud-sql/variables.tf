variable "workload_project_id" {
  description = "Project that owns the publishers and their operational database."
  type        = string
}

variable "terraform_operator_email" {
  description = "Google account email used by Terraform apply; it becomes the IAM database administrator for the provision script."
  type        = string
}

variable "region" {
  description = "Single region for the Cloud SQL instance and private network."
  type        = string
}

variable "network_name" {
  description = "Pre-existing Workload VPC name from the network root."
  type        = string
  default     = "workload-private"
}

variable "instance_name" {
  description = "Stable Cloud SQL instance identifier."
  type        = string
  default     = "workload-postgres"
}

variable "database_tier" {
  description = "Cloud SQL tier. db-f1-micro is a POC-only shared-core tier without an SLA."
  type        = string
  default     = "db-f1-micro"
}

variable "availability_type" {
  description = "Cloud SQL availability setting. Use REGIONAL before a production deployment."
  type        = string
  default     = "ZONAL"

  validation {
    condition     = contains(["ZONAL", "REGIONAL"], var.availability_type)
    error_message = "availability_type must be ZONAL or REGIONAL."
  }
}

variable "private_service_prefix_length" {
  description = "Prefix length of the address range reserved for private services access."
  type        = number
  default     = 16
}
