variable "cluster_name" {
  description = "Name of the EKS cluster to deploy to"
  type        = string
}

variable "aws_region" {
  description = "AWS region where the EKS cluster is running"
  type        = string
  default     = "us-east-1"
}

variable "app_name" {
  description = "Application name used for all Kubernetes resources"
  type        = string
  default     = "nginx-demo"
}

variable "namespace" {
  description = "Kubernetes namespace to deploy the application into"
  type        = string
  default     = "demo-app"
}

variable "replicas" {
  description = "Number of pod replicas for the deployment"
  type        = number
  default     = 3
}

variable "image" {
  description = "Container image to deploy"
  type        = string
  default     = "nginx:1.25-alpine"
}

variable "cpu_request" {
  description = "CPU request/limit for each pod (e.g., 100m, 250m, 1)"
  type        = string
  default     = "100m"
}

variable "memory_request" {
  description = "Memory request/limit for each pod (e.g., 128Mi, 256Mi, 1Gi)"
  type        = string
  default     = "128Mi"
}

variable "domain_name" {
  description = "Domain name for the Ingress rule (e.g., app.example.com)"
  type        = string
  default     = "app.example.com"
}
