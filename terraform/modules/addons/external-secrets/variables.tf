variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "oidc_provider_arn" {
  description = "ARN of the OIDC provider"
  type        = string
}

variable "oidc_provider_url" {
  description = "URL of the OIDC provider (without https://)"
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace"
  type        = string
  default     = "external-secrets"
}

variable "service_account_name" {
  description = "Name of the Kubernetes service account"
  type        = string
  default     = "external-secrets"
}

variable "chart_version" {
  description = "External Secrets Operator Helm chart version"
  type        = string
  default     = "0.10.5"
}

variable "install_crds" {
  description = "Install CRDs with the Helm chart"
  type        = bool
  default     = true
}

variable "replica_count" {
  description = "Number of operator replicas"
  type        = number
  default     = 2
}

variable "resources_requests_cpu" {
  description = "CPU request"
  type        = string
  default     = "50m"
}

variable "resources_requests_memory" {
  description = "Memory request"
  type        = string
  default     = "64Mi"
}

variable "resources_limits_cpu" {
  description = "CPU limit"
  type        = string
  default     = "100m"
}

variable "resources_limits_memory" {
  description = "Memory limit"
  type        = string
  default     = "128Mi"
}

variable "tags" {
  description = "Additional tags for resources"
  type        = map(string)
  default     = {}
}
