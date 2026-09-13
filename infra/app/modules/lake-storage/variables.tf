variable "project_id" {
  type        = string
  description = "GCP Project ID."
}

variable "location" {
  type        = string
  description = "Region for storage bucket and Artifact Registry."
}

variable "bucket_name" {
  type        = string
  description = "Globally unique lake storage bucket name."
}

variable "repository_id" {
  type        = string
  description = "Artifact Registry Docker repository ID."
  default     = "platform-images"
}
