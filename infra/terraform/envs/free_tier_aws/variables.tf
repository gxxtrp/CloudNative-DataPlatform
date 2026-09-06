variable "aws_region" {
  description = "AWS Region for Free Tier resources"
  type        = string
  default     = "ap-southeast-1" # Bangkok / Singapore
}

variable "project_prefix" {
  description = "Resource name prefix"
  type        = string
  default     = "data-platform"
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}
