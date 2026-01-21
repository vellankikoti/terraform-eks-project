variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where the cluster is deployed"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
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
  description = "Kubernetes namespace to install the controller"
  type        = string
  default     = "kube-system"
}

variable "service_account_name" {
  description = "Name of the Kubernetes service account"
  type        = string
  default     = "aws-load-balancer-controller"
}

variable "chart_version" {
  description = "Version of the Helm chart"
  type        = string
  default     = "1.6.2"
}

variable "replica_count" {
  description = "Number of controller replicas"
  type        = number
  default     = 2

  validation {
    condition     = var.replica_count >= 1
    error_message = "Replica count must be at least 1."
  }
}

variable "resources_limits_cpu" {
  description = "CPU limit for the controller"
  type        = string
  default     = "200m"
}

variable "resources_limits_memory" {
  description = "Memory limit for the controller"
  type        = string
  default     = "512Mi"
}

variable "resources_requests_cpu" {
  description = "CPU request for the controller"
  type        = string
  default     = "100m"
}

variable "resources_requests_memory" {
  description = "Memory request for the controller"
  type        = string
  default     = "256Mi"
}

variable "enable_shield" {
  description = "Enable AWS Shield Advanced integration"
  type        = bool
  default     = false
}

variable "enable_waf" {
  description = "Enable AWS WAF Classic integration"
  type        = bool
  default     = false
}

variable "enable_wafv2" {
  description = "Enable AWS WAFv2 integration"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Additional tags for resources"
  type        = map(string)
  default     = {}
}
