variable "project_id" {
  type        = string
  description = "GCP Project ID."
}

variable "region" {
  type        = string
  description = "Regional location for storage and registry."
}

variable "bucket_name" {
  type        = string
  description = "Globally unique lake storage bucket name."
}

variable "repository_id" {
  type        = string
  description = "Artifact Registry Docker repository ID."
  default     = "platform-dev-images"
}
