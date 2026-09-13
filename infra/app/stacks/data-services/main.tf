module "lake_storage" {
  source        = "../../modules/lake-storage"
  project_id    = var.project_id
  location      = var.region
  bucket_name   = var.bucket_name
  repository_id = var.repository_id
}
