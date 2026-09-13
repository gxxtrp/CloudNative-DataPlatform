resource "google_container_cluster" "primary" {
  project                  = var.project_id
  name                     = var.name
  location                 = var.region
  node_locations           = length(var.node_locations) > 0 ? var.node_locations : null
  network                  = var.network_id
  subnetwork               = var.subnetwork_id
  remove_default_node_pool = true
  initial_node_count       = 1
  deletion_protection      = var.deletion_protection

  ip_allocation_policy {
    cluster_secondary_range_name  = var.pod_range_name
    services_secondary_range_name = var.service_range_name
  }

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
    master_ipv4_cidr_block  = var.master_ipv4_cidr_block
  }

  control_plane_endpoints_config {
    dns_endpoint_config {
      allow_external_traffic = true
    }
  }

  datapath_provider = "ADVANCED_DATAPATH"


  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  addons_config {
    dns_cache_config {
      enabled = true
    }
    http_load_balancing {
      disabled = false
    }
  }

  logging_config {
    enable_components = ["SYSTEM_COMPONENTS", "WORKLOADS"]
  }

  monitoring_config {
    enable_components = ["SYSTEM_COMPONENTS"]
    managed_prometheus {
      enabled = true
    }
  }
}

resource "google_container_node_pool" "core" {
  project        = var.project_id
  name           = "core"
  location       = var.region
  node_locations = length(var.node_locations) > 0 ? var.node_locations : null
  cluster        = google_container_cluster.primary.name

  autoscaling {
    min_node_count = var.core_min_nodes
    max_node_count = var.core_max_nodes
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  node_config {
    machine_type    = var.core_machine_type
    service_account = var.node_service_account_email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]
    disk_size_gb    = var.disk_size_gb
    disk_type       = "pd-balanced"

    labels = {
      pool = "core"
    }

    tags = ["gke-node", "gke-core"]

    metadata = {
      disable-legacy-endpoints = "true"
    }

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }
  }
}

resource "google_container_node_pool" "compute" {
  project        = var.project_id
  name           = "compute"
  location       = var.region
  node_locations = length(var.node_locations) > 0 ? var.node_locations : null
  cluster        = google_container_cluster.primary.name

  autoscaling {
    min_node_count = var.compute_min_nodes
    max_node_count = var.compute_max_nodes
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  node_config {
    machine_type    = var.compute_machine_type
    service_account = var.node_service_account_email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]
    disk_size_gb    = var.disk_size_gb
    disk_type       = "pd-balanced"

    labels = {
      pool = "compute"
    }

    tags = ["gke-node", "gke-compute"]

    taint {
      key    = "workload"
      value  = "compute"
      effect = "NO_SCHEDULE"
    }

    metadata = {
      disable-legacy-endpoints = "true"
    }

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }
  }
}
