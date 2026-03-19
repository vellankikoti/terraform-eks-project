variable "enabled" {
  description = "Enable Splunk integration"
  type        = bool
  default     = false
}

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  default     = ""
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = ""
}

variable "namespace" {
  description = "Kubernetes namespace for Splunk collector"
  type        = string
  default     = "splunk"
}

variable "chart_version" {
  description = "Splunk OpenTelemetry Collector Helm chart version"
  type        = string
  default     = "0.108.0"
}

###################
# Splunk Platform (HEC) - For Splunk Cloud / Enterprise
###################

variable "splunk_platform_endpoint" {
  description = "Splunk HEC endpoint URL (e.g., https://splunk.example.com:8088/services/collector)"
  type        = string
  default     = ""
}

variable "splunk_hec_token" {
  description = "Splunk HEC token for authentication"
  type        = string
  default     = ""
  sensitive   = true
}

variable "splunk_index" {
  description = "Splunk index for logs"
  type        = string
  default     = "main"
}

variable "enable_metrics" {
  description = "Send metrics to Splunk Platform"
  type        = bool
  default     = true
}

variable "enable_logs" {
  description = "Send logs to Splunk Platform"
  type        = bool
  default     = true
}

###################
# Splunk Observability Cloud
###################

variable "splunk_observability_access_token" {
  description = "Splunk Observability Cloud access token"
  type        = string
  default     = ""
  sensitive   = true
}

variable "splunk_observability_realm" {
  description = "Splunk Observability Cloud realm (e.g., us0, us1, eu0)"
  type        = string
  default     = "us0"
}

###################
# Resource Configuration
###################

variable "agent_resources_limits_cpu" {
  description = "CPU limit for the agent DaemonSet"
  type        = string
  default     = "200m"
}

variable "agent_resources_limits_memory" {
  description = "Memory limit for the agent DaemonSet"
  type        = string
  default     = "500Mi"
}

variable "agent_resources_requests_cpu" {
  description = "CPU request for the agent DaemonSet"
  type        = string
  default     = "100m"
}

variable "agent_resources_requests_memory" {
  description = "Memory request for the agent DaemonSet"
  type        = string
  default     = "256Mi"
}

variable "enable_gateway" {
  description = "Enable gateway collector for trace aggregation"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Additional tags for resources"
  type        = map(string)
  default     = {}
}
