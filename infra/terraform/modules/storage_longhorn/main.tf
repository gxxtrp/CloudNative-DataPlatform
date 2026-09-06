terraform {
  required_version = ">= 1.5.0"
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.13.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.30.0"
    }
  }
}

resource "helm_release" "longhorn" {
  name             = "longhorn"
  repository       = "https://charts.longhorn.io"
  chart            = "longhorn"
  version          = var.chart_version
  namespace        = "longhorn-system"
  create_namespace = false

  set {
    name  = "defaultSettings.defaultDataPath"
    value = var.data_path
  }

  set {
    name  = "defaultSettings.defaultReplicaCount"
    value = tostring(var.replica_count)
  }

  set {
    name  = "persistence.defaultClass"
    value = "true"
  }

  set {
    name  = "persistence.defaultClassReplicaCount"
    value = tostring(var.replica_count)
  }

  # Expose Longhorn UI on NodePort 30088
  set {
    name  = "service.ui.type"
    value = "NodePort"
  }

  set {
    name  = "service.ui.nodePort"
    value = "30088"
  }
}

resource "kubernetes_storage_class" "longhorn_isolated" {
  metadata {
    name = "longhorn-isolated"
    annotations = {
      "storageclass.kubernetes.io/is-default-class" = "true"
    }
  }

  storage_provisioner = "driver.longhorn.io"
  reclaim_policy      = "Delete"
  volume_binding_mode = "Immediate"

  parameters = {
    numberOfReplicas    = tostring(var.replica_count)
    staleReplicaTimeout = "30"
    dataLocality        = "best-effort"
  }

  depends_on = [helm_release.longhorn]
}
