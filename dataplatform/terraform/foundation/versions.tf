terraform {
  required_version = ">= 1.7.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 6.0, < 8.0"
    }
  }

  # This root owns only Data Platform resources. Its state never shares a
  # bucket or prefix with the Workload root.
  backend "gcs" {
    bucket = "dataplatform-508107-tf-state"
    prefix = "foundation"
  }
}

provider "google" {
  project = var.dataplatform_project_id
  region  = var.region
}
