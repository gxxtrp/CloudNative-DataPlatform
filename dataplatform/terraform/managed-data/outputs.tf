output "storage_buckets" {
  description = "Private Cloud Storage zones keyed by their data responsibility."
  value = {
    for key, bucket in google_storage_bucket.data : key => {
      name     = bucket.name
      location = bucket.location
      url      = bucket.url
    }
  }
}

output "bigquery_datasets" {
  description = "Empty regional datasets reserved for staging, curated, and operational data."
  value = {
    for key, dataset in google_bigquery_dataset.data : key => dataset.dataset_id
  }
}
