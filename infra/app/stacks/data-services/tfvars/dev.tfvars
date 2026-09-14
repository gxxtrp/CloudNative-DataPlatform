project_id    = "sbx-workload-poc-508107"
region        = "asia-southeast1"
repository_id = "platform-dev-images"

# Medallion Data Lake Storage Tiers
buckets = {
  bronze = {
    name                       = "sbx-workload-poc-508107-lake-bronze-dev"
    storage_class              = "STANDARD"
    versioning                 = true
    retention_days             = 90
    noncurrent_version_days    = 7
    soft_delete_retention_days = 0
  },
  silver = {
    name                       = "sbx-workload-poc-508107-lake-silver-dev"
    storage_class              = "STANDARD"
    versioning                 = true
    noncurrent_version_days    = 7
    soft_delete_retention_days = 0
  },
  gold = {
    name                       = "sbx-workload-poc-508107-lake-gold-dev"
    storage_class              = "STANDARD"
    versioning                 = true
    noncurrent_version_days    = 7
    soft_delete_retention_days = 0
  },
  artifacts = {
    name                       = "sbx-workload-poc-508107-argo-artifacts-dev"
    storage_class              = "STANDARD"
    versioning                 = false
    retention_days             = 30
    noncurrent_version_days    = null
    soft_delete_retention_days = 0
  }
}
