locals {
  services = toset([
    "serviceusage.googleapis.com",
    "compute.googleapis.com",
    "container.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "storage.googleapis.com",
    "artifactregistry.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
  ])
}

resource "google_project_service" "required" {
  for_each           = local.services
  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

module "network" {
  source       = "../../modules/network"
  project_id   = var.project_id
  region       = var.region
  name         = var.name
  node_cidr    = var.node_cidr
  pod_cidr     = var.pod_cidr
  service_cidr = var.service_cidr
  depends_on   = [google_project_service.required]
}

resource "google_service_account" "nodes" {
  project      = var.project_id
  account_id   = "${var.name}-nodes"
  display_name = "GKE node infrastructure identity"
  depends_on   = [google_project_service.required]
}

resource "google_project_iam_member" "nodes" {
  project = var.project_id
  role    = "roles/container.defaultNodeServiceAccount"
  member  = "serviceAccount:${google_service_account.nodes.email}"
}
