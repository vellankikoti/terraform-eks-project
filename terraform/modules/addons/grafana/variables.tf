variable "namespace" {
  description = "Kubernetes namespace to install Grafana"
  type        = string
  default     = "grafana"
}

variable "chart_version" {
  description = "Version of the Grafana Helm chart"
  type        = string
  default     = "7.3.9"
}

variable "admin_user" {
  description = "Grafana admin username"
  type        = string
  default     = "admin"
}

variable "admin_password" {
  description = "Grafana admin password (do NOT commit real secrets)"
  type        = string
  default     = "admin"
}

variable "replica_count" {
  description = "Number of Grafana replicas"
  type        = number
  default     = 1
}

variable "resources_limits_cpu" {
  description = "CPU limit for Grafana"
  type        = string
  default     = "500m"
}

variable "resources_limits_memory" {
  description = "Memory limit for Grafana"
  type        = string
  default     = "512Mi"
}

variable "resources_requests_cpu" {
  description = "CPU request for Grafana"
  type        = string
  default     = "250m"
}

variable "resources_requests_memory" {
  description = "Memory request for Grafana"
  type        = string
  default     = "256Mi"
}

variable "ingress_enabled" {
  description = "Enable ingress for Grafana"
  type        = bool
  default     = false
}

variable "ingress_class_name" {
  description = "Ingress class name for Grafana"
  type        = string
  default     = "alb"
}

variable "ingress_host" {
  description = "Hostname for Grafana ingress"
  type        = string
  default     = "grafana.example.com"
}

variable "prometheus_url" {
  description = "URL for Prometheus datasource (e.g., http://kube-prometheus-stack-prometheus.monitoring.svc:9090)"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Additional tags for resources"
  type        = map(string)
  default     = {}
}

