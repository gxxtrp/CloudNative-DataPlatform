data "google_compute_network" "workload" {
  project = var.workload_project_id
  name    = var.network_name
}

locals {
  publisher_service_accounts = {
    order = {
      account_id   = "order-publisher"
      display_name = "Order publisher runtime"
    }
    rider = {
      account_id   = "rider-publisher"
      display_name = "Rider publisher runtime"
    }
  }

  publisher_database_users = {
    for key, service_account in google_service_account.publisher :
    key => trimsuffix(service_account.email, ".gserviceaccount.com")
  }
}

# Cloud SQL consumes addresses from this private-services range. It is separate
# from the Cloud Run subnet, and no Cloud SQL public IPv4 address is allocated.
resource "google_compute_global_address" "private_services" {
  project       = var.workload_project_id
  name          = "workload-private-services"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = var.private_service_prefix_length
  network       = data.google_compute_network.workload.id
}

resource "google_service_networking_connection" "private_services" {
  network                 = data.google_compute_network.workload.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_services.name]
}

resource "google_sql_database_instance" "workload" {
  project             = var.workload_project_id
  name                = var.instance_name
  region              = var.region
  database_version    = "POSTGRES_15"
  deletion_protection = true
  deletion_policy     = "PREVENT"

  settings {
    tier              = var.database_tier
    edition           = "ENTERPRISE"
    availability_type = var.availability_type
    disk_type         = "PD_SSD"
    disk_size         = 10
    disk_autoresize   = true
    user_labels = {
      system      = "delivery-data-platform"
      environment = "poc"
      managed_by  = "terraform"
    }

    backup_configuration {
      enabled                        = true
      point_in_time_recovery_enabled = true
      transaction_log_retention_days = 7
    }

    database_flags {
      name  = "cloudsql.iam_authentication"
      value = "on"
    }

    data_api_access = "ALLOW_DATA_API"

    ip_configuration {
      ipv4_enabled                                  = false
      private_network                               = data.google_compute_network.workload.id
      allocated_ip_range                            = google_compute_global_address.private_services.name
      enable_private_path_for_google_cloud_services = true
    }
  }

  depends_on = [google_service_networking_connection.private_services]
}

resource "google_sql_database" "workload" {
  project  = var.workload_project_id
  name     = "delivery_workload"
  instance = google_sql_database_instance.workload.name
}

# Publisher identities use IAM database authentication; neither a database
# password nor a service-account key is created or stored in Terraform state.
resource "google_service_account" "publisher" {
  for_each = local.publisher_service_accounts

  project      = var.workload_project_id
  account_id   = each.value.account_id
  display_name = each.value.display_name
}

resource "google_project_iam_member" "publisher_cloud_sql_client" {
  for_each = google_service_account.publisher

  project = var.workload_project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${each.value.email}"
}

resource "google_project_iam_member" "publisher_cloud_sql_instance_user" {
  for_each = google_service_account.publisher

  project = var.workload_project_id
  role    = "roles/cloudsql.instanceUser"
  member  = "serviceAccount:${each.value.email}"
}

# The Terraform operator is deliberately the only database administrator. It
# authenticates with ADC and runs an idempotent bootstrap through the Cloud SQL
# Data API; publisher identities receive only their own schemas.
resource "google_project_iam_member" "terraform_operator_cloud_sql_instance_user" {
  project = var.workload_project_id
  role    = "roles/cloudsql.instanceUser"
  member  = "user:${var.terraform_operator_email}"
}

resource "google_sql_user" "terraform_operator" {
  project         = var.workload_project_id
  instance        = google_sql_database_instance.workload.name
  name            = var.terraform_operator_email
  type            = "CLOUD_IAM_USER"
  database_roles  = ["cloudsqlsuperuser"]
  deletion_policy = "ABANDON"
}

resource "google_sql_user" "publisher" {
  for_each = google_service_account.publisher

  project  = var.workload_project_id
  instance = google_sql_database_instance.workload.name
  # Cloud SQL PostgreSQL IAM users omit the .gserviceaccount.com suffix.
  name            = local.publisher_database_users[each.key]
  type            = "CLOUD_IAM_SERVICE_ACCOUNT"
  deletion_policy = "ABANDON"
}

resource "google_sql_provision_script" "publisher_schemas" {
  project     = var.workload_project_id
  instance    = google_sql_database_instance.workload.name
  database    = google_sql_database.workload.name
  description = "Create isolated publisher schemas and runtime privileges"
  script      = <<-SQL
    REVOKE ALL ON SCHEMA public FROM PUBLIC;
    -- The Terraform operator owns the schemas. A Cloud SQL IAM database
    -- administrator cannot transfer ownership to an unrelated IAM role.
    CREATE SCHEMA IF NOT EXISTS order_service;
    CREATE SCHEMA IF NOT EXISTS rider_service;
    GRANT CONNECT ON DATABASE ${google_sql_database.workload.name} TO "${local.publisher_database_users.order}", "${local.publisher_database_users.rider}";
    GRANT USAGE, CREATE ON SCHEMA order_service TO "${local.publisher_database_users.order}";
    GRANT USAGE, CREATE ON SCHEMA rider_service TO "${local.publisher_database_users.rider}";
  SQL

  depends_on = [
    google_project_iam_member.terraform_operator_cloud_sql_instance_user,
    google_sql_user.terraform_operator,
    google_sql_user.publisher,
  ]
}
