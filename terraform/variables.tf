variable "cluster_name" {
  description = "Nom du cluster kind"
  type        = string
  default     = "greenlogistics"
}

variable "namespaces" {
  description = "Namespaces applicatifs à créer"
  type        = list(string)
  default     = ["app", "messaging", "mail", "vault", "external-secrets", "monitoring", "argocd", "kubecost"]
}

variable "argocd_chart_version" {
  description = "Version du chart ArgoCD"
  type        = string
  default     = "6.7.0"
}

variable "redpanda_chart_version" {
  description = "Version du chart Redpanda"
  type        = string
  default     = "5.8.6"
}

variable "kps_chart_version" {
  description = "Version du chart kube-prometheus-stack"
  type        = string
  default     = "58.2.2"
}
