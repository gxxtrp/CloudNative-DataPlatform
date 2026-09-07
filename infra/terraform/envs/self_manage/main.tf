terraform {
  required_version = ">= 1.5.0"
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.30.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.14.0"
    }
  }
}

provider "kubernetes" {
  config_path = pathexpand(var.kubeconfig_path)
}

provider "helm" {
  kubernetes {
    config_path = pathexpand(var.kubeconfig_path)
  }
}

# ------------------------------------------------------------------------------
# Module 1: Base Kubernetes Namespaces (Prerequisite for all deployments)
# ------------------------------------------------------------------------------
module "k8s_base" {
  source      = "../../modules/k8s_base"
  environment = "self_manage"
}

# ------------------------------------------------------------------------------
# Module 2: GitOps Substrate (ArgoCD Core & Argo Workflows)
# ArgoCD takes over Day-1/Day-2 deployment for all platform engines,
# Kafka topics, MinIO buckets, Gateway API ingress, and application workloads.
# Note: Storage is provided natively by k3s built-in local-path provisioner.
# ------------------------------------------------------------------------------
module "gitops_argo" {
  source = "../../modules/gitops_argo"

  depends_on = [module.k8s_base]
}
