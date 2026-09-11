# GKE Cluster Stack

locals {
  cluster_name = "${var.gke_cluster_name}-${var.env}"
}

# GKE Cluster
module "gke" {
  source  = "terraform-google-modules/kubernetes-engine/google//modules/private-cluster"
  version = "~> 31.0"

  project_id = var.project_id
  name       = local.cluster_name
  region     = var.region

  network           = var.network_name
  subnetwork        = "${var.network_name}-subnet"
  ip_range_pods     = "${var.network_name}-pods"
  ip_range_services = "${var.network_name}-services"

  # Private cluster configuration
  enable_private_nodes    = true
  enable_private_endpoint = false
  master_ipv4_cidr_block  = "172.16.0.0/28"

  # Node pool configuration
  remove_default_node_pool = true

  node_pools = [
    {
      name               = "platform-pool"
      machine_type       = var.gke_node_machine_type
      min_count          = 1
      max_count          = var.gke_node_count
      disk_size_gb       = 100
      disk_type          = "pd-standard"
      auto_repair        = true
      auto_upgrade       = true
      preemptible        = var.env != "prod"
    },
    {
      name               = "spark-pool"
      machine_type       = "e2-standard-8"
      min_count          = 0
      max_count          = 10
      disk_size_gb       = 200
      disk_type          = "pd-ssd"
      auto_repair        = true
      auto_upgrade       = true
      preemptible        = var.env != "prod"
      
      # Taint for Spark workloads only
      node_taints = var.env == "prod" ? [] : [
        {
          key    = "workload"
          value  = "spark"
          effect = "NO_SCHEDULE"
        }
      ]
    },
    {
      name               = "flink-pool"
      machine_type       = "e2-standard-4"
      min_count          = 1
      max_count          = 5
      disk_size_gb       = 100
      disk_type          = "pd-ssd"
      auto_repair        = true
      auto_upgrade       = true
      preemptible        = false  # Flink needs stable nodes
    }
  ]

  node_pools_labels = {
    all = {
      env = var.env
    }
    platform-pool = {
      workload = "platform"
    }
    spark-pool = {
      workload = "spark"
    }
    flink-pool = {
      workload = "flink"
    }
  }

  # Workload Identity
  workload_identity_config = {
    workload_pool = "${var.project_id}.svc.id.goog"
  }
}

# Outputs
output "cluster_name" {
  value = module.gke.name
}

output "cluster_endpoint" {
  value     = module.gke.endpoint
  sensitive = true
}

output "cluster_ca_certificate" {
  value     = module.gke.ca_certificate
  sensitive = true
}
