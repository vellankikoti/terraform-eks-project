variable "cluster_name" {
  description = "Name of the EKS cluster"
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
  description = "Kubernetes namespace to install the autoscaler"
  type        = string
  default     = "kube-system"
}

variable "service_account_name" {
  description = "Name of the Kubernetes service account"
  type        = string
  default     = "cluster-autoscaler"
}

variable "chart_version" {
  description = "Version of the Helm chart"
  type        = string
  default     = "9.29.3"
}

variable "expander" {
  description = "Type of node group expander to use (random, most-pods, least-waste, priority)"
  type        = string
  default     = "least-waste"

  validation {
    condition     = contains(["random", "most-pods", "least-waste", "priority"], var.expander)
    error_message = "Expander must be one of: random, most-pods, least-waste, priority."
  }
}

variable "scale_down_enabled" {
  description = "Should cluster autoscaler scale down nodes"
  type        = bool
  default     = true
}

variable "scale_down_delay_after_add" {
  description = "How long after scale up that scale down evaluation resumes"
  type        = string
  default     = "10m"
}

variable "scale_down_unneeded_time" {
  description = "How long a node should be unneeded before it is eligible for scale down"
  type        = string
  default     = "10m"
}

variable "scale_down_utilization_threshold" {
  description = "Node utilization level below which a node can be considered for scale down"
  type        = string
  default     = "0.5"
}

variable "resources_limits_cpu" {
  description = "CPU limit for the autoscaler"
  type        = string
  default     = "100m"
}

variable "resources_limits_memory" {
  description = "Memory limit for the autoscaler"
  type        = string
  default     = "300Mi"
}

variable "resources_requests_cpu" {
  description = "CPU request for the autoscaler"
  type        = string
  default     = "100m"
}

variable "resources_requests_memory" {
  description = "Memory request for the autoscaler"
  type        = string
  default     = "300Mi"
}

variable "tags" {
  description = "Additional tags for resources"
  type        = map(string)
  default     = {}
}
