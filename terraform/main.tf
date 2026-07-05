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
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
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
    value = "512Mi"
  }
  set {
    name  = "prometheus.prometheusSpec.resources.limits.memory"
    value = "1Gi"
  }
  set {
    name  = "alertmanager.enabled"
    value = "true"
  }

  # matcherStrategy=None : les routes des objets AlertmanagerConfig ne se voient
  # pas forcer un matcher namespace=. Le routage → MailHog est défini dans le CR
  # AlertmanagerConfig `k8s/monitoring/alertmanager-mailhog.yaml` (GitOps), qui
  # matche les alertes team="greenlogistics".
  set {
    name  = "alertmanager.alertmanagerSpec.alertmanagerConfigMatcherStrategy.type"
    value = "None"
  }
}

# ── Redpanda — manifest direct (chart Helm incompatible avec kind low-memory) ─
resource "null_resource" "redpanda" {
  depends_on = [module.namespaces]

  provisioner "local-exec" {
    command = "kubectl --context kind-greenlogistics apply -f ${path.module}/../k8s/redpanda/statefulset.yaml"
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
  set {
    name  = "backend.replicas"
    value = "0"
  }
  set {
    name  = "read.replicas"
    value = "0"
  }
  set {
    name  = "write.replicas"
    value = "0"
  }
  set {
    name  = "loki.useTestSchema"
    value = "true"
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

# ── Linkerd — cert generation + install via null_resource ────────────────────
resource "null_resource" "linkerd" {
  provisioner "local-exec" {
    command = "${path.module}/scripts/install-linkerd.sh"
  }
}

# ── Argo Rollouts ─────────────────────────────────────────────────────────────
resource "helm_release" "argo_rollouts" {
  name             = "argo-rollouts"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-rollouts"
  namespace        = "argo-rollouts"
  create_namespace = true
  timeout          = 300
}

# ── External Secrets Operator ─────────────────────────────────────────────────
resource "helm_release" "external_secrets" {
  name             = "external-secrets"
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  namespace        = "external-secrets"
  create_namespace = false
  depends_on       = [module.namespaces]
  timeout          = 300
}
