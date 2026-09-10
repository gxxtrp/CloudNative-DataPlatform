terraform {
  required_version = ">= 1.7.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 6.0, < 8.0"
    }
  }

  backend "gcs" {
    bucket = "workload-508107-tf-state"
    prefix = "cloud-sql"
  }
}

provider "google" {
  project = var.workload_project_id
  region  = var.region
}
