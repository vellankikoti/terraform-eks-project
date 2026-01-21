variable "cluster_name" {
  description = "Name of the EKS cluster (for tagging)"
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace to install Metrics Server"
  type        = string
  default     = "kube-system"
}

variable "chart_version" {
  description = "Version of the Metrics Server Helm chart"
  type        = string
  default     = "3.11.0"
}

variable "replica_count" {
  description = "Number of Metrics Server replicas (for HA)"
  type        = number
  default     = 2

  validation {
    condition     = var.replica_count >= 1
    error_message = "Replica count must be at least 1."
  }
}

variable "resources_limits_cpu" {
  description = "CPU limit for Metrics Server"
  type        = string
  default     = "100m"
}

variable "resources_limits_memory" {
  description = "Memory limit for Metrics Server"
  type        = string
  default     = "200Mi"
}

variable "resources_requests_cpu" {
  description = "CPU request for Metrics Server"
  type        = string
  default     = "100m"
}

variable "resources_requests_memory" {
  description = "Memory request for Metrics Server"
  type        = string
  default     = "200Mi"
}

variable "node_selector_value" {
  description = "Node selector value for Metrics Server (optional)"
  type        = string
  default     = null
}

variable "tolerations" {
  description = "Tolerations for Metrics Server pods"
  type = list(object({
    key      = string
    operator = optional(string, "Equal")
    value    = optional(string)
    effect   = optional(string, "NoSchedule")
  }))
  default = []
}

variable "tags" {
  description = "Additional tags for resources"
  type        = map(string)
  default     = {}
}
