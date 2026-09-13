variable "project_id" {
  type        = string
  description = "Existing billed GCP project; project creation is outside this stack."
}
variable "region" {
  type        = string
  description = "Region chosen after the M0 cost and network review."
}
variable "name" {
  type        = string
  description = "Foundation resource prefix."
  default     = "platform-dev"
}
variable "node_cidr" {
  type = string
}
variable "pod_cidr" {
  type = string
}
variable "service_cidr" {
  type = string
}
variable "deployment_reviewed" {
  type        = bool
  default     = false
  description = "True only after recording region, CIDR conflicts, access, credit expiry and baseline cost."
  validation {
    condition     = var.deployment_reviewed
    error_message = "Complete the M0 deployment review before planning or applying foundation."
  }
}
