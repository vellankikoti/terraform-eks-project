variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "prod"
}

variable "project_name" {
  description = "Project name"
  type        = string
  default     = "myapp"
}

###################
# VPC Variables
###################

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "az_count" {
  description = "Number of availability zones (production: use 3+ for HA)"
  type        = number
  default     = 3

  validation {
    condition     = var.az_count >= 2 && var.az_count <= 6
    error_message = "AZ count must be between 2 and 6."
  }
}

variable "enable_nat_gateway" {
  description = "Enable NAT Gateway (production: true for HA)"
  type        = bool
  default     = true
}

variable "create_database_subnets" {
  description = "Create database subnets"
  type        = bool
  default     = true  # Production: Enable for RDS/ElastiCache isolation
}

variable "enable_flow_logs" {
  description = "Enable VPC Flow Logs (production: true for security monitoring)"
  type        = bool
  default     = true
}

variable "enable_s3_endpoint" {
  description = "Enable S3 VPC endpoint"
  type        = bool
  default     = true
}

variable "enable_dynamodb_endpoint" {
  description = "Enable DynamoDB VPC endpoint"
  type        = bool
  default     = true
}

variable "enable_ecr_endpoints" {
  description = "Enable ECR VPC endpoints (production: true for better performance)"
  type        = bool
  default     = true
}

###################
# EKS Variables
###################

variable "cluster_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.28"
}

variable "endpoint_private_access" {
  description = "Enable private API endpoint (production: true)"
  type        = bool
  default     = true
}

variable "endpoint_public_access" {
  description = "Enable public API endpoint (production: restrict with CIDRs)"
  type        = bool
  default     = true
}

variable "public_access_cidrs" {
  description = "CIDR blocks allowed to access public API endpoint (production: restrict to office IPs)"
  type        = list(string)
  default     = ["0.0.0.0/0"]  # TODO: Replace with actual office IPs
}

variable "enabled_cluster_log_types" {
  description = "Control plane logging types (production: enable all)"
  type        = list(string)
  default     = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
}

variable "log_retention_days" {
  description = "CloudWatch log retention days (production: longer retention)"
  type        = number
  default     = 30  # Production: 30 days minimum
}

variable "enable_ssm" {
  description = "Enable SSM for node management (production: true for debugging)"
  type        = bool
  default     = true
}

variable "node_groups" {
  description = "EKS node group configurations (production: larger instances, more nodes)"
  type = map(object({
    desired_size    = number
    max_size        = number
    min_size        = number
    instance_types  = list(string)
    capacity_type   = optional(string)
    disk_size       = optional(number)
    max_unavailable = optional(number)
    labels          = optional(map(string))
    taints = optional(list(object({
      key    = string
      value  = optional(string)
      effect = string
    })))
    tags                = optional(map(string))
    bootstrap_arguments = optional(string)
  }))

  default = {
    general = {
      desired_size   = 3  # Production: Minimum 3 for HA
      max_size       = 10
      min_size        = 3
      instance_types = ["m5.large"]  # Production: Larger instances
      capacity_type  = "ON_DEMAND"   # Production: On-demand for stability
      disk_size      = 100
    }
  }
}

###################
# Add-on Variables
###################

variable "alb_controller_replica_count" {
  description = "Number of AWS Load Balancer Controller replicas (production: 2+ for HA)"
  type        = number
  default     = 2
}

variable "metrics_server_replica_count" {
  description = "Number of Metrics Server replicas (production: 2+ for HA)"
  type        = number
  default     = 2
}

variable "autoscaler_scale_down_enabled" {
  description = "Enable cluster autoscaler scale down"
  type        = bool
  default     = true
}

variable "autoscaler_scale_down_delay_after_add" {
  description = "Scale down delay after scale up"
  type        = string
  default     = "10m"
}

variable "autoscaler_scale_down_unneeded_time" {
  description = "Time before unneeded node is scaled down"
  type        = string
  default     = "10m"
}

variable "autoscaler_scale_down_utilization_threshold" {
  description = "Node utilization threshold for scale down"
  type        = string
  default     = "0.5"
}

###################
# Optional Add-ons Variables
###################

variable "route53_zone_ids" {
  description = "Route53 hosted zone IDs (for External DNS and Cert-Manager)"
  type        = list(string)
  default     = []
}

variable "domain_filters" {
  description = "Domain filters for External DNS"
  type        = list(string)
  default     = []
}

variable "cert_manager_enable_route53" {
  description = "Enable Route53 for Cert-Manager DNS01 challenge"
  type        = bool
  default     = false
}
