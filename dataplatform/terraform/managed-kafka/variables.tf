variable "dataplatform_project_id" {
  description = "Project that owns the Managed Kafka cluster and its ACLs."
  type        = string
}

variable "dataplatform_project_number" {
  description = "Immutable number of the project that owns the Managed Kafka service agent."
  type        = string
}

variable "workload_project_id" {
  description = "Project that owns the publisher subnet and Cloud Run identities."
  type        = string
}

variable "region" {
  description = "Single region for the cluster and its connected subnets."
  type        = string
}

variable "workload_kafka_subnet_name" {
  description = "Name of the pre-existing Workload subnet in which Kafka PSC endpoints are created."
  type        = string
  default     = "workload-run"
}

variable "cluster_id" {
  description = "Stable Managed Kafka cluster identifier."
  type        = string
  default     = "delivery-poc"
}

variable "vcpu_count" {
  description = "Total cluster vCPU count. Managed Kafka has ongoing regional compute charges."
  type        = number
  default     = 3
}

variable "memory_bytes" {
  description = "Total cluster memory in bytes."
  type        = number
  default     = 3221225472
}

variable "topic_retention_ms" {
  description = "Retention period for synthetic producer topics."
  type        = number
  default     = 604800000
}
