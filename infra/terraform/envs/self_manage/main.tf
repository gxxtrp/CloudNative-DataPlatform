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
# Module 2: Longhorn Distributed CSI Storage (Prerequisite for PVCs)
# ------------------------------------------------------------------------------
module "storage_longhorn" {
  source        = "../../modules/storage_longhorn"
  data_path     = "/data/k3s-storage"
  replica_count = 2

  depends_on = [module.k8s_base]
}

# ------------------------------------------------------------------------------
# Module 3: GitOps Substrate (ArgoCD Core & Argo Workflows)
# ArgoCD takes over Day-1/Day-2 deployment for all platform engines,
# Kafka topics, MinIO buckets, Gateway API ingress, and application workloads.
# ------------------------------------------------------------------------------
module "gitops_argo" {
  source = "../../modules/gitops_argo"

  depends_on = [module.k8s_base]
}
