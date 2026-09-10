locals {
  common_labels = {
    system      = "delivery-data-platform"
    environment = var.environment
    data_class  = "synthetic"
    managed_by  = "terraform"
  }

  buckets = {
    raw = {
      name           = "${var.dataplatform_project_id}-raw"
      retention_days = var.raw_retention_days
      layer          = "raw"
    }
    quarantine = {
      name           = "${var.dataplatform_project_id}-quarantine"
      retention_days = var.quarantine_retention_days
      layer          = "quarantine"
    }
    checkpoints = {
      name           = "${var.dataplatform_project_id}-checkpoints"
      retention_days = var.transient_retention_days
      layer          = "checkpoints"
    }
    artifacts = {
      name           = "${var.dataplatform_project_id}-artifacts"
      retention_days = var.transient_retention_days
      layer          = "artifacts"
    }
  }
}

# Each storage layer is a separate resource so IAM can later grant a processor
# only the least access needed for its declared input and output paths.
resource "google_storage_bucket" "data" {
  for_each = local.buckets

  project                     = var.dataplatform_project_id
  name                        = each.value.name
  location                    = var.region
  storage_class               = "STANDARD"
  force_destroy               = false
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  labels                      = merge(local.common_labels, { layer = each.value.layer })

  versioning {
    enabled = true
  }

  lifecycle_rule {
    action {
      type = "Delete"
    }
    condition {
      age = each.value.retention_days
    }
  }

  # Deleting a live version makes it archived when versioning is enabled. This
  # second rule ensures POC buckets do not retain superseded object versions
  # indefinitely and quietly accumulate storage cost.
  lifecycle_rule {
    action {
      type = "Delete"
    }
    condition {
      age        = each.value.retention_days
      with_state = "ARCHIVED"
    }
  }
}

# Datasets are empty on creation. Dataset-level ownership remains with this
# root; later transformations expose consumers through curated views.
resource "google_bigquery_dataset" "data" {
  for_each = toset(["staging", "curated", "operations"])

  project                    = var.dataplatform_project_id
  dataset_id                 = "delivery_${each.value}"
  friendly_name              = "Delivery ${title(each.value)}"
  description                = "Synthetic Delivery Data Platform ${each.value} dataset."
  location                   = var.region
  delete_contents_on_destroy = false
  labels                     = merge(local.common_labels, { layer = each.value })
}
