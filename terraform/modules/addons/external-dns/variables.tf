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

variable "route53_zone_ids" {
  description = "List of Route53 hosted zone IDs that External DNS can manage"
  type        = list(string)
}

variable "namespace" {
  description = "Kubernetes namespace to install External DNS"
  type        = string
  default     = "kube-system"
}

variable "service_account_name" {
  description = "Name of the Kubernetes service account"
  type        = string
  default     = "external-dns"
}

variable "chart_version" {
  description = "Version of the External DNS Helm chart"
  type        = string
  default     = "6.14.2"
}

variable "zone_type" {
  description = "Route53 zone type (public, private)"
  type        = string
  default     = "public"

  validation {
    condition     = contains(["public", "private"], var.zone_type)
    error_message = "zone_type must be either public or private."
  }
}

variable "domain_filters" {
  description = "List of domains to filter (only manage these domains)"
  type        = list(string)
  default     = []
}

variable "txt_owner_id" {
  description = "TXT record owner ID (prevents conflicts with multiple External DNS instances)"
  type        = string
  default     = null
}

variable "policy" {
  description = "DNS record management policy (sync, upsert-only, create-only)"
  type        = string
  default     = "sync"

  validation {
    condition     = contains(["sync", "upsert-only", "create-only"], var.policy)
    error_message = "policy must be one of: sync, upsert-only, create-only."
  }
}

variable "sources" {
  description = "List of sources to watch for DNS records (ingress, service, crd)"
  type        = list(string)
  default     = ["ingress", "service"]

  validation {
    condition     = length(var.sources) > 0
    error_message = "At least one source must be specified."
  }
}

variable "replica_count" {
  description = "Number of External DNS replicas"
  type        = number
  default     = 2

  validation {
    condition     = var.replica_count >= 1
    error_message = "Replica count must be at least 1."
  }
}

variable "resources_limits_cpu" {
  description = "CPU limit for External DNS"
  type        = string
  default     = "100m"
}

variable "resources_limits_memory" {
  description = "Memory limit for External DNS"
  type        = string
  default     = "128Mi"
}

variable "resources_requests_cpu" {
  description = "CPU request for External DNS"
  type        = string
  default     = "50m"
}

variable "resources_requests_memory" {
  description = "Memory request for External DNS"
  type        = string
  default     = "64Mi"
}

variable "log_level" {
  description = "Log level (debug, info, warning, error)"
  type        = string
  default     = "info"

  validation {
    condition     = contains(["debug", "info", "warning", "error"], var.log_level)
    error_message = "log_level must be one of: debug, info, warning, error."
  }
}

variable "log_format" {
  description = "Log format (text, json)"
  type        = string
  default     = "text"

  validation {
    condition     = contains(["text", "json"], var.log_format)
    error_message = "log_format must be either text or json."
  }
}

variable "tags" {
  description = "Additional tags for resources"
  type        = map(string)
  default     = {}
}
