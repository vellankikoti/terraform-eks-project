variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "aws_region" {
  description = "AWS region (for tagging/consistency)"
  type        = string
}

variable "oidc_provider_arn" {
  description = "ARN of the OIDC provider for the EKS cluster"
  type        = string
}

variable "oidc_provider_url" {
  description = "URL of the OIDC provider (without https://)"
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace to install ArgoCD"
  type        = string
  default     = "argocd"
}

variable "service_account_name" {
  description = "Name of the Kubernetes service account for ArgoCD server"
  type        = string
  default     = "argocd-server"
}

variable "chart_version" {
  description = "Version of the ArgoCD Helm chart"
  type        = string
  default     = "5.51.6"
}

variable "enable_irsa" {
  description = "Enable IRSA for ArgoCD (required if ArgoCD needs AWS API access)"
  type        = bool
  default     = false
}

variable "iam_policy_json" {
  description = "Optional IAM policy JSON for ArgoCD when IRSA is enabled"
  type        = string
  default     = ""
}

variable "server_replica_count" {
  description = "Number of ArgoCD server replicas"
  type        = number
  default     = 2
}

variable "server_resources_limits_cpu" {
  description = "CPU limit for ArgoCD server"
  type        = string
  default     = "500m"
}

variable "server_resources_limits_memory" {
  description = "Memory limit for ArgoCD server"
  type        = string
  default     = "512Mi"
}

variable "server_resources_requests_cpu" {
  description = "CPU request for ArgoCD server"
  type        = string
  default     = "250m"
}

variable "server_resources_requests_memory" {
  description = "Memory request for ArgoCD server"
  type        = string
  default     = "256Mi"
}

variable "ingress_enabled" {
  description = "Enable ingress for ArgoCD server"
  type        = bool
  default     = false
}

variable "ingress_class_name" {
  description = "Ingress class name for ArgoCD server ingress"
  type        = string
  default     = "alb"
}

variable "ingress_host" {
  description = "Hostname for ArgoCD server ingress (e.g., argocd.example.com)"
  type        = string
  default     = "argocd.example.com"
}

variable "tags" {
  description = "Additional tags for resources"
  type        = map(string)
  default     = {}
}

