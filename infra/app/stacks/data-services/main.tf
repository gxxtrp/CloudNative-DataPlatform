module "lake_storage" {
  source        = "../../modules/lake-storage"
  project_id    = var.project_id
  location      = var.region
  buckets       = var.buckets
  repository_id = var.repository_id
}
