variable "namespace" {
  description = "Kubernetes namespace"
  type        = string
  default     = "kube-system"
}

variable "chart_version" {
  description = "VPA Helm chart version"
  type        = string
  default     = "9.8.3"
}

variable "recommender_enabled" {
  description = "Enable VPA recommender (always enable - it's the core component)"
  type        = bool
  default     = true
}

variable "updater_enabled" {
  description = "Enable VPA updater (caution: restarts pods to apply new resource values)"
  type        = bool
  default     = false  # Off by default for safety in production
}

variable "enable_admission_controller" {
  description = "Enable admission controller (sets resources on new pods)"
  type        = bool
  default     = true
}

variable "resources_requests_cpu" {
  description = "CPU request for recommender"
  type        = string
  default     = "50m"
}

variable "resources_requests_memory" {
  description = "Memory request for recommender"
  type        = string
  default     = "500Mi"
}

variable "resources_limits_cpu" {
  description = "CPU limit for recommender"
  type        = string
  default     = "200m"
}

variable "resources_limits_memory" {
  description = "Memory limit for recommender"
  type        = string
  default     = "1Gi"
}

variable "tags" {
  description = "Additional tags"
  type        = map(string)
  default     = {}
}
