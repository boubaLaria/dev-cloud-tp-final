terraform {
  required_version = ">= 1.7"
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.27"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.13"
    }
  }
  backend "local" {
    path = "state/terraform.tfstate"
  }
}

# ── Providers — cluster kind existant ────────────────────────────────────────
provider "kubernetes" {
  config_path    = "~/.kube/config"
  config_context = "kind-greenlogistics"
}

provider "helm" {
  kubernetes {
    config_path    = "~/.kube/config"
    config_context = "kind-greenlogistics"
  }
}

# ── Namespaces ────────────────────────────────────────────────────────────────
module "namespaces" {
  source     = "./modules/namespace-rbac"
  namespaces = var.namespaces
}

# ── ArgoCD ────────────────────────────────────────────────────────────────────
resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = var.argocd_chart_version
  namespace        = "argocd"
  create_namespace = false
  depends_on       = [module.namespaces]

  set {
    name  = "server.service.type"
    value = "NodePort"
  }
  set {
    name  = "server.service.nodePortHttp"
    value = "30080"
  }
}

# ── kube-prometheus-stack ────────────────────────────────────────────────────
resource "helm_release" "kube_prometheus_stack" {
  name             = "kps"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  version          = var.kps_chart_version
  namespace        = "monitoring"
  create_namespace = false
  depends_on       = [module.namespaces]
  timeout          = 600

  set {
    name  = "grafana.service.type"
    value = "NodePort"
  }
  set {
    name  = "grafana.service.nodePort"
    value = "30090"
  }
  set {
    name  = "prometheus.prometheusSpec.retention"
    value = "2d"
  }
  set {
    name  = "prometheus.prometheusSpec.resources.requests.memory"
    value = "256Mi"
  }
  set {
    name  = "prometheus.prometheusSpec.resources.limits.memory"
    value = "512Mi"
  }
  set {
    name  = "alertmanager.enabled"
    value = "true"
  }
}

# ── Redpanda ─────────────────────────────────────────────────────────────────
resource "helm_release" "redpanda" {
  name             = "redpanda"
  repository       = "https://charts.redpanda.com"
  chart            = "redpanda"
  version          = var.redpanda_chart_version
  namespace        = "messaging"
  create_namespace = false
  depends_on       = [module.namespaces]
  timeout          = 300

  set {
    name  = "statefulset.replicas"
    value = "1"
  }
  set {
    name  = "resources.cpu.cores"
    value = "1"
  }
  set {
    name  = "resources.memory.container.max"
    value = "1Gi"
  }
  set {
    name  = "tls.enabled"
    value = "false"
  }
  set {
    name  = "external.enabled"
    value = "false"
  }
}

# ── Vault (dev-mode) ──────────────────────────────────────────────────────────
resource "helm_release" "vault" {
  name             = "vault"
  repository       = "https://helm.releases.hashicorp.com"
  chart            = "vault"
  namespace        = "vault"
  create_namespace = false
  depends_on       = [module.namespaces]

  set {
    name  = "server.dev.enabled"
    value = "true"
  }
  set {
    name  = "server.dev.devRootToken"
    value = "root"
  }
}

# ── Loki ─────────────────────────────────────────────────────────────────────
resource "helm_release" "loki" {
  name             = "loki"
  repository       = "https://grafana.github.io/helm-charts"
  chart            = "loki"
  namespace        = "monitoring"
  create_namespace = false
  depends_on       = [module.namespaces]

  set {
    name  = "deploymentMode"
    value = "SingleBinary"
  }
  set {
    name  = "loki.commonConfig.replication_factor"
    value = "1"
  }
  set {
    name  = "loki.storage.type"
    value = "filesystem"
  }
  set {
    name  = "singleBinary.replicas"
    value = "1"
  }
}

# ── Promtail ──────────────────────────────────────────────────────────────────
resource "helm_release" "promtail" {
  name             = "promtail"
  repository       = "https://grafana.github.io/helm-charts"
  chart            = "promtail"
  namespace        = "monitoring"
  create_namespace = false
  depends_on       = [helm_release.loki]

  set {
    name  = "config.clients[0].url"
    value = "http://loki.monitoring.svc.cluster.local:3100/loki/api/v1/push"
  }
}
