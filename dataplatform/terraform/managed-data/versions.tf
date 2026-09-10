terraform {
  required_version = ">= 1.7.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 6.0, < 8.0"
    }
  }

  # This root has its own prefix in the Data Platform state bucket. It never
  # shares state with the foundation, Workload, or a local checkout.
  backend "gcs" {
    bucket = "dataplatform-508107-tf-state"
    prefix = "managed-data"
  }
}

provider "google" {
  project = var.dataplatform_project_id
  region  = var.region
}
