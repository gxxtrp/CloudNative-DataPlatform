terraform {
  required_version = ">= 1.8.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "= 7.40.0"
    }
  }
}

provider "google" {
  project = var.project_id
}

variable "project_id" {
  type        = string
  description = "Existing project with Cloud Storage API and billing enabled."
}
variable "bucket_name" {
  type        = string
  description = "Globally unique state bucket name."
}
variable "location" {
  type        = string
  description = "Reviewed regional state bucket location."
}

resource "google_storage_bucket" "state" {
  project                     = var.project_id
  name                        = var.bucket_name
  location                    = var.location
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = false

  versioning {
    enabled = true
  }
  lifecycle {
    prevent_destroy = true
  }
}

output "bucket_name" {
  value = google_storage_bucket.state.name
}
