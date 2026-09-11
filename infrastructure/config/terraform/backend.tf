# GCS backend for Terraform state
# Terraspace automatically configures bucket per environment

terraform {
  backend "gcs" {
    # Configured via Terraspace
    # bucket = "dataplatform-${env}-tfstate"
    # prefix = "terraspace/${stack}"
  }
}
