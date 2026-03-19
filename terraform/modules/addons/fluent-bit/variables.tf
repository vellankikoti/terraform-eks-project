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
  default     = "logging"
}

variable "service_account_name" {
  description = "Name of the Kubernetes service account"
  type        = string
  default     = "fluent-bit"
}

variable "chart_version" {
  description = "Fluent Bit Helm chart version"
  type        = string
  default     = "0.47.10"
}

variable "cloudwatch_log_group_name" {
  description = "CloudWatch Logs group name"
  type        = string
  default     = "/eks/fluent-bit"
}

variable "cloudwatch_log_retention_days" {
  description = "CloudWatch Logs retention in days"
  type        = number
  default     = 7
}

variable "enable_s3_output" {
  description = "Enable S3 log output for archival"
  type        = bool
  default     = false
}

variable "s3_bucket_name" {
  description = "S3 bucket for log archival (required if enable_s3_output is true)"
  type        = string
  default     = ""
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
  default     = "200m"
}

variable "resources_limits_memory" {
  description = "Memory limit"
  type        = string
  default     = "256Mi"
}

variable "tags" {
  description = "Additional tags for resources"
  type        = map(string)
  default     = {}
}
