terraform {
  required_version = ">= 1.5.0"
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.13.0"
    }
  }
}

# ------------------------------------------------------------------------------
# ArgoCD Core (GitOps Deployment Engine)
# ------------------------------------------------------------------------------
resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = var.argocd_chart_version
  namespace        = "argocd"
  create_namespace = false

  # Lightweight Core Mode (saves ~200MB RAM)
  set {
    name  = "server.service.type"
    value = "NodePort"
  }

  set {
    name  = "server.service.nodePortHttp"
    value = "30080"
  }

  set {
    name  = "server.service.nodePortHttps"
    value = "30443"
  }

  set {
    name  = "server.insecure"
    value = "true"
  }

  set {
    name  = "dex.enabled"
    value = "false"
  }

  set {
    name  = "notifications.enabled"
    value = "false"
  }
}

# ------------------------------------------------------------------------------
# Argo Workflows (Native Kubernetes Batch DAG Orchestrator)
# ------------------------------------------------------------------------------
resource "helm_release" "argo_workflows" {
  name             = "argo-workflows"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-workflows"
  version          = var.argo_workflows_chart_version
  namespace        = "argo-workflow"
  create_namespace = false

  set {
    name  = "server.serviceType"
    value = "NodePort"
  }

  set {
    name  = "server.serviceNodePort"
    value = "32746"
  }

  set {
    name  = "server.authMode"
    value = "server"
  }

  set {
    name  = "controller.workflowNamespaces[0]"
    value = "argo-workflow"
  }

  set {
    name  = "controller.workflowNamespaces[1]"
    value = "platform"
  }

  set {
    name  = "controller.workflowNamespaces[2]"
    value = "apps"
  }
}
