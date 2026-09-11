# GKE Stack Variables

variable "project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "region" {
  description = "GCP Region"
  type        = string
}

variable "env" {
  description = "Environment (dev, staging, prod)"
  type        = string
}

variable "network_name" {
  description = "VPC network name"
  type        = string
}

variable "gke_cluster_name" {
  description = "GKE cluster name"
  type        = string
}

variable "gke_node_count" {
  description = "Number of nodes per pool"
  type        = number
  default     = 3
}

variable "gke_node_machine_type" {
  description = "Machine type for GKE nodes"
  type        = string
  default     = "e2-standard-4"
}

variable "gke_enable_autopilot" {
  description = "Enable GKE Autopilot mode"
  type        = bool
  default     = false
}
