terraform {
  required_version = ">= 1.5.0"
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.30.0"
    }
  }
}

resource "kubernetes_namespace" "namespaces" {
  for_each = toset(var.namespaces)

  metadata {
    name = each.key
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "environment"                  = var.environment
      "platform.data/tier"           = each.key == "platform" ? "data-plane" : (each.key == "apps" ? "workloads" : (each.key == "observability" ? "observability" : (each.key == "argocd" ? "control-plane" : "system")))
    }
  }
}
