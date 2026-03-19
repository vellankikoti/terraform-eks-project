variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "cluster_endpoint" {
  description = "EKS cluster API endpoint"
  type        = string
}

variable "cluster_arn" {
  description = "ARN of the EKS cluster"
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

variable "node_role_arn" {
  description = "ARN of the IAM role for Karpenter-launched nodes"
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace for Karpenter"
  type        = string
  default     = "kube-system"
}

variable "service_account_name" {
  description = "Name of the Kubernetes service account"
  type        = string
  default     = "karpenter"
}

variable "chart_version" {
  description = "Karpenter Helm chart version"
  type        = string
  default     = "1.0.7"
}

variable "replica_count" {
  description = "Number of Karpenter controller replicas"
  type        = number
  default     = 2
}

variable "resources_requests_cpu" {
  description = "CPU request for controller"
  type        = string
  default     = "250m"
}

variable "resources_requests_memory" {
  description = "Memory request for controller"
  type        = string
  default     = "256Mi"
}

variable "resources_limits_cpu" {
  description = "CPU limit for controller"
  type        = string
  default     = "1000m"
}

variable "resources_limits_memory" {
  description = "Memory limit for controller"
  type        = string
  default     = "1Gi"
}

variable "tags" {
  description = "Additional tags for resources"
  type        = map(string)
  default     = {}
}
