terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.27"
    }
  }
}

# Crée les namespaces avec labels standards
resource "kubernetes_namespace" "namespaces" {
  for_each = toset(var.namespaces)

  metadata {
    name = each.value
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "team"                         = "greenlogistics"
      "env"                          = "production"
    }
  }
}

# ServiceAccount de base par namespace applicatif
resource "kubernetes_service_account" "default_sa" {
  for_each = toset(["app"])

  metadata {
    name      = "default-sa"
    namespace = each.value
    labels = {
      team = "greenlogistics"
      env  = "production"
    }
  }

  depends_on = [kubernetes_namespace.namespaces]
}

# Role lecture des secrets dans namespace app
resource "kubernetes_role" "secret_reader" {
  metadata {
    name      = "secret-reader"
    namespace = "app"
    labels = {
      team = "greenlogistics"
    }
  }

  rule {
    api_groups = [""]
    resources  = ["secrets", "configmaps"]
    verbs      = ["get", "list", "watch"]
  }

  depends_on = [kubernetes_namespace.namespaces]
}
