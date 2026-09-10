resource "google_artifact_registry_repository" "publishers" {
  project       = var.workload_project_id
  location      = var.region
  repository_id = "delivery-workload"
  description   = "Private OCI images for the Delivery publisher modules."
  format        = "DOCKER"
  labels = {
    system      = "delivery-data-platform"
    environment = "poc"
    managed_by  = "terraform"
  }
}
