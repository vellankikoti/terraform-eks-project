variable "namespace" {
  description = "Kubernetes namespace to install Reloader"
  type        = string
  default     = "reloader"
}

variable "chart_version" {
  description = "Version of the Reloader Helm chart"
  type        = string
  default     = "1.0.118"
}

variable "watch_globally" {
  description = "Watch ConfigMaps/Secrets in all namespaces"
  type        = bool
  default     = true
}

variable "resources_limits_cpu" {
  description = "CPU limit for Reloader"
  type        = string
  default     = "200m"
}

variable "resources_limits_memory" {
  description = "Memory limit for Reloader"
  type        = string
  default     = "256Mi"
}

variable "resources_requests_cpu" {
  description = "CPU request for Reloader"
  type        = string
  default     = "100m"
}

variable "resources_requests_memory" {
  description = "Memory request for Reloader"
  type        = string
  default     = "128Mi"
}

variable "tags" {
  description = "Additional tags for resources"
  type        = map(string)
  default     = {}
}

