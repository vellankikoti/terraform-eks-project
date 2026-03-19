variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "staging"
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
  description = "CIDR block for VPC (staging uses 10.20.0.0/16)"
  type        = string
  default     = "10.20.0.0/16"  # Unique: dev=10.10, staging=10.20, prod=10.0
}

variable "az_count" {
  description = "Number of availability zones"
  type        = number
  default     = 2

  validation {
    condition     = var.az_count >= 2 && var.az_count <= 6
    error_message = "AZ count must be between 2 and 6."
  }
}

variable "enable_nat_gateway" {
  description = "Enable NAT Gateway"
  type        = bool
  default     = true
}

variable "create_database_subnets" {
  description = "Create database subnets"
  type        = bool
  default     = true  # Staging: test database connectivity
}

variable "enable_flow_logs" {
  description = "Enable VPC Flow Logs"
  type        = bool
  default     = true
}

variable "enable_s3_endpoint" {
  description = "Enable S3 VPC endpoint (free)"
  type        = bool
  default     = true
}

variable "enable_dynamodb_endpoint" {
  description = "Enable DynamoDB VPC endpoint (free)"
  type        = bool
  default     = true
}

variable "enable_ecr_endpoints" {
  description = "Enable ECR VPC endpoints"
  type        = bool
  default     = true  # Staging: match prod to catch endpoint-related issues
}

###################
# EKS Variables
###################

variable "cluster_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.31"
}

variable "endpoint_private_access" {
  description = "Enable private API endpoint"
  type        = bool
  default     = true
}

variable "endpoint_public_access" {
  description = "Enable public API endpoint"
  type        = bool
  default     = true
}

variable "public_access_cidrs" {
  description = "CIDR blocks allowed to access public API endpoint"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "enabled_cluster_log_types" {
  description = "Control plane logging types"
  type        = list(string)
  default     = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
}

variable "log_retention_days" {
  description = "CloudWatch log retention days"
  type        = number
  default     = 14
}

variable "enable_ssm" {
  description = "Enable SSM for node management"
  type        = bool
  default     = true
}

variable "node_groups" {
  description = "EKS node group configurations"
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

  # Staging: Production-like but smaller scale
  # Mixed ON_DEMAND + SPOT for cost optimization
  default = {
    system = {
      desired_size   = 2
      max_size       = 4
      min_size       = 2
      instance_types = ["t3.large"]
      capacity_type  = "ON_DEMAND"
      disk_size      = 50
      labels = {
        "workload-type" = "system"
      }
    }
    workload-spot = {
      desired_size   = 2
      max_size       = 8
      min_size       = 1
      instance_types = ["t3.large", "t3a.large", "m5.large", "m5a.large"]
      capacity_type  = "SPOT"
      disk_size      = 50
      labels = {
        "workload-type" = "general"
        "lifecycle"     = "spot"
      }
    }
  }
}

###################
# Add-on Variables
###################

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
# Optional Add-on Variables
###################

variable "route53_zone_ids" {
  description = "Route53 hosted zone IDs"
  type        = list(string)
  default     = []
}

variable "cert_manager_enable_route53" {
  description = "Enable Route53 for Cert-Manager DNS01 challenge"
  type        = bool
  default     = false
}
