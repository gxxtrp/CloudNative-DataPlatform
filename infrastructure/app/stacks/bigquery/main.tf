# BigQuery Stack - Datasets and BigLake connections

# Create datasets for each layer
resource "google_bigquery_dataset" "datasets" {
  for_each = toset(var.bigquery_datasets)

  dataset_id = each.value
  project    = var.project_id
  location   = var.bigquery_location

  labels = {
    env   = var.env
    layer = each.value
  }

  # Default table expiration (none for production)
  default_table_expiration_ms = var.env == "prod" ? null : 2592000000 # 30 days
}

# BigLake connection for Iceberg tables
resource "google_bigquery_connection" "biglake" {
  connection_id = "biglake-${var.env}"
  project       = var.project_id
  location      = var.bigquery_location

  cloud_resource {}
}

# Grant BigLake connection access to GCS bucket
resource "google_project_iam_member" "biglake_gcs_access" {
  project = var.project_id
  role    = "roles/storage.objectViewer"
  member  = "serviceAccount:${google_bigquery_connection.biglake.cloud_resource[0].service_account_id}"
}

# BigQuery Metastore for Iceberg catalog
resource "google_bigquery_dataset" "iceberg_catalog" {
  dataset_id = "iceberg_catalog"
  project    = var.project_id
  location   = var.bigquery_location

  labels = {
    env     = var.env
    purpose = "iceberg-metadata"
  }
}

# Outputs
output "dataset_ids" {
  value = { for k, v in google_bigquery_dataset.datasets : k => v.dataset_id }
}

output "biglake_connection_id" {
  value = google_bigquery_connection.biglake.connection_id
}

output "biglake_service_account" {
  value = google_bigquery_connection.biglake.cloud_resource[0].service_account_id
}
