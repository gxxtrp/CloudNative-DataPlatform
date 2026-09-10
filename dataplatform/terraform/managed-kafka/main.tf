locals {
  workload_subnet = join("/", [
    "projects", var.workload_project_id,
    "regions", var.region,
    "subnetworks", var.workload_kafka_subnet_name,
  ])

  publisher_principals = [
    "User:order-publisher@${var.workload_project_id}.iam.gserviceaccount.com",
    "User:rider-publisher@${var.workload_project_id}.iam.gserviceaccount.com",
  ]

  topic_publishers = {
    "orders.lifecycle" = [local.publisher_principals[0]]
    "riders.telemetry" = [local.publisher_principals[1]]
  }

  topics = toset(keys(local.topic_publishers))
}

# Enabling an API does not always materialize its Google-managed identity until
# the first API call. Generate it before the cross-project IAM grant, otherwise
# the grant can race the service-agent creation.
resource "google_project_service_identity" "managed_kafka" {
  provider = google-beta
  project  = var.dataplatform_project_id
  service  = "managedkafka.googleapis.com"
}

# The cluster's Google-managed agent can create Kafka PSC endpoints and private
# DNS entries only in the designated Workload subnet. No broad project access
# or Shared VPC is used.
resource "google_project_iam_member" "kafka_service_agent_workload_network" {
  project = var.workload_project_id
  role    = "roles/managedkafka.serviceAgent"
  member  = google_project_service_identity.managed_kafka.member
}

resource "google_managed_kafka_cluster" "delivery" {
  project    = var.dataplatform_project_id
  cluster_id = var.cluster_id
  location   = var.region
  labels = {
    system      = "delivery-data-platform"
    environment = "poc"
    managed_by  = "terraform"
  }

  capacity_config {
    vcpu_count   = var.vcpu_count
    memory_bytes = var.memory_bytes
  }

  gcp_config {
    access_config {
      network_configs {
        subnet = local.workload_subnet
      }
    }
  }

  depends_on = [google_project_iam_member.kafka_service_agent_workload_network]
}

resource "google_managed_kafka_topic" "events" {
  for_each = local.topics

  project            = var.dataplatform_project_id
  location           = var.region
  cluster            = google_managed_kafka_cluster.delivery.cluster_id
  topic_id           = each.value
  partition_count    = 3
  replication_factor = 3
  configs = {
    "retention.ms" = tostring(var.topic_retention_ms)
  }
}

# ACLs grant only the two publisher identities write access to their event
# topics. The eventual intake identity receives read access in its own phase.
resource "google_managed_kafka_acl" "publisher_topics" {
  for_each = local.topics

  project  = var.dataplatform_project_id
  location = var.region
  cluster  = google_managed_kafka_cluster.delivery.cluster_id
  acl_id   = "topic/${each.value}"

  dynamic "acl_entries" {
    for_each = local.topic_publishers[each.value]
    content {
      principal       = acl_entries.value
      operation       = "WRITE"
      permission_type = "ALLOW"
      host            = "*"
    }
  }
}

# ACLs control topic operations; this IAM role separately permits each
# Workload identity to establish an authenticated Managed Kafka session.
resource "google_project_iam_member" "publisher_managed_kafka_client" {
  for_each = toset(local.publisher_principals)

  project = var.dataplatform_project_id
  role    = "roles/managedkafka.client"
  member  = "serviceAccount:${trimprefix(each.value, "User:")}"
}
