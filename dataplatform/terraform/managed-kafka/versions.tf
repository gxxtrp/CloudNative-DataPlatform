terraform {
  required_version = ">= 1.7.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 6.0, < 8.0"
    }
  }

  backend "gcs" {
    bucket = "dataplatform-508107-tf-state"
    prefix = "managed-kafka"
  }
}

provider "google" {
  project = var.dataplatform_project_id
  region  = var.region
}
