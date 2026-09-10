locals {
  platform_context = {
    private_connectivity_only = var.private_connectivity_only
    region                    = var.region
    synthetic_data_only       = var.synthetic_data_only
  }

  dataplatform_products = toset([
    "artifactregistry.googleapis.com",
    "bigquery.googleapis.com",
    "billingbudgets.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "compute.googleapis.com",
    "container.googleapis.com",
    "dataform.googleapis.com",
    "iamcredentials.googleapis.com",
    "iam.googleapis.com",
    "logging.googleapis.com",
    "managedkafka.googleapis.com",
    "monitoring.googleapis.com",
    "secretmanager.googleapis.com",
    "storage.googleapis.com",
    "sts.googleapis.com",
  ])
}

# The two projects are created and billing-linked before this module runs. This
# avoids a circular dependency between project creation and the GCS backend.
resource "google_project_service" "dataplatform" {
  for_each = local.dataplatform_products

  project            = var.dataplatform_project_id
  service            = each.value
  disable_on_destroy = false
}
