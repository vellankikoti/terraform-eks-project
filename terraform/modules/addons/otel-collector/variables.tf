variable "namespace" {
  description = "Kubernetes namespace to install OpenTelemetry Collector"
  type        = string
  default     = "observability"
}

variable "chart_version" {
  description = "Version of the OpenTelemetry Collector Helm chart"
  type        = string
  default     = "0.93.1"
}

variable "mode" {
  description = "Deployment mode: deployment or daemonset"
  type        = string
  default     = "deployment"
}

variable "replica_count" {
  description = "Number of replicas (for deployment mode)"
  type        = number
  default     = 2
}

variable "resources_limits_cpu" {
  description = "CPU limit for the collector"
  type        = string
  default     = "500m"
}

variable "resources_limits_memory" {
  description = "Memory limit for the collector"
  type        = string
  default     = "512Mi"
}

variable "resources_requests_cpu" {
  description = "CPU request for the collector"
  type        = string
  default     = "250m"
}

variable "resources_requests_memory" {
  description = "Memory request for the collector"
  type        = string
  default     = "256Mi"
}

variable "config_yaml" {
  description = "OpenTelemetry Collector configuration (YAML string)"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Additional tags for resources"
  type        = map(string)
  default     = {}
}

