data "terraform_remote_state" "cloud_sql" {
  backend = "gcs"

  config = {
    bucket = "workload-508107-tf-state"
    prefix = "cloud-sql"
  }
}

data "google_compute_network" "workload" {
  project = var.workload_project_id
  name    = var.network_name
}

data "google_compute_subnetwork" "cloud_run" {
  project = var.workload_project_id
  region  = var.region
  name    = var.subnetwork_name
}

locals {
  publishers = {
    order = {
      image                  = var.order_image
      container_port         = 8080
      topic                  = "orders.lifecycle"
      service_account_key    = "order"
      cloud_run_service_name = "order-publisher"
    }
    rider = {
      image                  = var.rider_image
      container_port         = 8081
      topic                  = "riders.telemetry"
      service_account_key    = "rider"
      cloud_run_service_name = "rider-publisher"
    }
  }
}

# These modules are internally reachable only. Direct VPC egress routes Cloud
# SQL private IP and Kafka PSC traffic through the Workload VPC without a
# Serverless VPC Access connector, public IP, or Cloud NAT gateway.
resource "google_cloud_run_v2_service" "publisher" {
  for_each = local.publishers

  project             = var.workload_project_id
  name                = each.value.cloud_run_service_name
  location            = var.region
  ingress             = "INGRESS_TRAFFIC_INTERNAL_ONLY"
  deletion_protection = var.deletion_protection
  labels = {
    system      = "delivery-data-platform"
    environment = "poc"
    module      = "${each.key}-publisher"
    managed_by  = "terraform"
  }

  template {
    service_account                  = data.terraform_remote_state.cloud_sql.outputs.publisher_service_accounts[each.value.service_account_key]
    timeout                          = "30s"
    max_instance_request_concurrency = 80

    scaling {
      min_instance_count = 0
      max_instance_count = 2
    }

    vpc_access {
      egress = "PRIVATE_RANGES_ONLY"

      network_interfaces {
        network    = data.google_compute_network.workload.id
        subnetwork = data.google_compute_subnetwork.cloud_run.id
        tags       = ["workload-publisher"]
      }
    }

    containers {
      image = each.value.image

      ports {
        container_port = each.value.container_port
      }

      resources {
        limits = {
          cpu    = "1"
          memory = "512Mi"
        }
        cpu_idle          = true
        startup_cpu_boost = true
      }

      env {
        name  = "DATABASE_HOST"
        value = data.terraform_remote_state.cloud_sql.outputs.private_ip_address
      }
      env {
        name  = "DATABASE_NAME"
        value = data.terraform_remote_state.cloud_sql.outputs.database_name
      }
      env {
        name  = "DATABASE_USER"
        value = data.terraform_remote_state.cloud_sql.outputs.publisher_database_users[each.value.service_account_key]
      }
      env {
        name  = "CLOUD_SQL_INSTANCE"
        value = data.terraform_remote_state.cloud_sql.outputs.instance_connection_name
      }
      env {
        name  = "KAFKA_BOOTSTRAP_SERVERS"
        value = var.kafka_bootstrap_servers
      }
      env {
        name  = "KAFKA_TOPIC"
        value = each.value.topic
      }
      env {
        name  = "KAFKA_CLIENT_EMAIL"
        value = data.terraform_remote_state.cloud_sql.outputs.publisher_service_accounts[each.value.service_account_key]
      }
    }
  }
}
