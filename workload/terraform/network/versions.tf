terraform {
  required_version = ">= 1.7.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 6.0, < 8.0"
    }
  }

  # This state contains only the Workload VPC. The Data Platform cannot write
  # it, even though Managed Kafka is later granted access to this subnet.
  backend "gcs" {
    bucket = "workload-508107-tf-state"
    prefix = "network"
  }
}

provider "google" {
  project = var.workload_project_id
  region  = var.region
}
