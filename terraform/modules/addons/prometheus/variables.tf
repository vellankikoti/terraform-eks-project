variable "namespace" {
  description = "Kubernetes namespace to install kube-prometheus-stack"
  type        = string
  default     = "monitoring"
}

variable "chart_version" {
  description = "Version of the kube-prometheus-stack Helm chart"
  type        = string
  default     = "65.5.1"
}

variable "prometheus_replica_count" {
  description = "Number of Prometheus replicas"
  type        = number
  default     = 1
}

variable "prometheus_resources_limits_cpu" {
  description = "CPU limit for Prometheus"
  type        = string
  default     = "1000m"
}

variable "prometheus_resources_limits_memory" {
  description = "Memory limit for Prometheus"
  type        = string
  default     = "2Gi"
}

variable "prometheus_resources_requests_cpu" {
  description = "CPU request for Prometheus"
  type        = string
  default     = "500m"
}

variable "prometheus_resources_requests_memory" {
  description = "Memory request for Prometheus"
  type        = string
  default     = "1Gi"
}

variable "enable_builtin_grafana" {
  description = "Enable built-in Grafana from kube-prometheus-stack"
  type        = bool
  default     = false
}

variable "ingress_enabled" {
  description = "Enable ingress for Prometheus"
  type        = bool
  default     = false
}

variable "ingress_class_name" {
  description = "Ingress class name for Prometheus"
  type        = string
  default     = "alb"
}

variable "ingress_host" {
  description = "Hostname for Prometheus ingress"
  type        = string
  default     = "prometheus.example.com"
}

variable "tags" {
  description = "Additional tags for resources"
  type        = map(string)
  default     = {}
}

