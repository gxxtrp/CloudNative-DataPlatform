variable "project_id" {
  type        = string
  description = "Project that owns the network."
}
variable "region" {
  type        = string
  description = "Reviewed subnet and NAT region."
}
variable "name" {
  type        = string
  description = "Network name and resource prefix."
}
variable "node_cidr" {
  type        = string
  description = "Reviewed primary IPv4 range for GKE nodes."
  validation {
    condition     = can(cidrnetmask(var.node_cidr))
    error_message = "node_cidr must be an IPv4 CIDR."
  }
}
variable "pod_cidr" {
  type        = string
  description = "Reviewed secondary IPv4 range for Pods."
  validation {
    condition     = can(cidrnetmask(var.pod_cidr))
    error_message = "pod_cidr must be an IPv4 CIDR."
  }
}
variable "service_cidr" {
  type        = string
  description = "Reviewed secondary IPv4 range for Services."
  validation {
    condition     = can(cidrnetmask(var.service_cidr))
    error_message = "service_cidr must be an IPv4 CIDR."
  }
}
