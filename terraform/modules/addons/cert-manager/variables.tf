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
  description = "Kubernetes namespace to install Cert-Manager"
  type        = string
  default     = "cert-manager"
}

variable "service_account_name" {
  description = "Name of the Kubernetes service account"
  type        = string
  default     = "cert-manager"
}

variable "chart_version" {
  description = "Version of the Cert-Manager Helm chart"
  type        = string
  default     = "v1.13.3"
}

variable "install_crds" {
  description = "Install Cert-Manager CRDs"
  type        = bool
  default     = true
}

variable "enable_route53" {
  description = "Enable Route53 DNS01 challenge support (requires IAM permissions)"
  type        = bool
  default     = true
}

variable "route53_zone_ids" {
  description = "List of Route53 hosted zone IDs for DNS01 challenge (required if enable_route53 is true)"
  type        = list(string)
  default     = []
}

variable "resources_limits_cpu" {
  description = "CPU limit for Cert-Manager controller"
  type        = string
  default     = "100m"
}

variable "resources_limits_memory" {
  description = "Memory limit for Cert-Manager controller"
  type        = string
  default     = "128Mi"
}

variable "resources_requests_cpu" {
  description = "CPU request for Cert-Manager controller"
  type        = string
  default     = "50m"
}

variable "resources_requests_memory" {
  description = "Memory request for Cert-Manager controller"
  type        = string
  default     = "64Mi"
}

variable "prometheus_enabled" {
  description = "Enable Prometheus metrics"
  type        = bool
  default     = true
}

variable "webhook_replica_count" {
  description = "Number of webhook replicas"
  type        = number
  default     = 2

  validation {
    condition     = var.webhook_replica_count >= 1
    error_message = "Webhook replica count must be at least 1."
  }
}

variable "startupapicheck_enabled" {
  description = "Enable startup API check"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Additional tags for resources"
  type        = map(string)
  default     = {}
}
