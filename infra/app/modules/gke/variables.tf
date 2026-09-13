variable "project_id" {
  type        = string
  description = "GCP Project ID."
}

variable "region" {
  type        = string
  description = "Regional location for the GKE cluster."
}

variable "name" {
  type        = string
  description = "Cluster name."
  default     = "platform-dev"
}

variable "node_locations" {
  type        = list(string)
  description = "Specific zones where nodes should be placed. Leave single zone for bounded dev sizing."
  default     = []
}

variable "network_id" {
  type        = string
  description = "VPC network ID or self link."
}

variable "subnetwork_id" {
  type        = string
  description = "Subnetwork ID or self link."
}

variable "pod_range_name" {
  type        = string
  description = "Secondary IP range name for Pods."
}

variable "service_range_name" {
  type        = string
  description = "Secondary IP range name for Services."
}

variable "master_ipv4_cidr_block" {
  type        = string
  description = "Reserved /28 CIDR for the GKE control plane."
  default     = "172.16.0.0/28"
}

variable "node_service_account_email" {
  type        = string
  description = "Service account email to attach to worker nodes."
}

variable "core_machine_type" {
  type        = string
  description = "Machine type for the core node pool."
  default     = "e2-standard-4"
}

variable "core_min_nodes" {
  type        = number
  description = "Minimum nodes for the core pool."
  default     = 1
}

variable "core_max_nodes" {
  type        = number
  description = "Maximum nodes for the core pool."
  default     = 2
}

variable "compute_machine_type" {
  type        = string
  description = "Machine type for the compute node pool."
  default     = "e2-standard-4"
}

variable "compute_min_nodes" {
  type        = number
  description = "Minimum nodes for the compute pool (scale-to-zero)."
  default     = 0
}

variable "compute_max_nodes" {
  type        = number
  description = "Maximum nodes for the compute pool."
  default     = 2
}

variable "disk_size_gb" {
  type        = number
  description = "Boot disk size in GB for worker nodes."
  default     = 50
}

variable "deletion_protection" {
  type        = bool
  description = "Whether to protect the cluster from deletion."
  default     = false
}
