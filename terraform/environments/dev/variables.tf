variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
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
  description = "CIDR block for VPC (dev uses 10.10.0.0/16 to avoid overlap with prod)"
  type        = string
  default     = "10.10.0.0/16"  # Unique per environment to allow VPC peering
}

variable "az_count" {
  description = "Number of availability zones (dev: 2 for cost savings)"
  type        = number
  default     = 2
}

variable "enable_nat_gateway" {
  description = "Enable NAT Gateway"
  type        = bool
  default     = true
}

variable "create_database_subnets" {
  description = "Create database subnets"
  type        = bool
  default     = false  # Dev: not needed unless testing RDS
}

variable "enable_flow_logs" {
  description = "Enable VPC Flow Logs"
  type        = bool
  default     = false  # Dev: disabled to save cost
}

variable "enable_s3_endpoint" {
  description = "Enable S3 VPC endpoint (free - always enable)"
  type        = bool
  default     = true
}

variable "enable_dynamodb_endpoint" {
  description = "Enable DynamoDB VPC endpoint (free - always enable)"
  type        = bool
  default     = true
}

variable "enable_ecr_endpoints" {
  description = "Enable ECR VPC endpoints (~$14/month - dev: disabled)"
  type        = bool
  default     = false
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
  default     = ["0.0.0.0/0"]  # Dev: open for convenience
}

variable "enabled_cluster_log_types" {
  description = "Control plane logging types"
  type        = list(string)
  default     = ["api", "audit", "authenticator"]  # Dev: reduced logging
}

variable "log_retention_days" {
  description = "CloudWatch log retention days"
  type        = number
  default     = 3  # Dev: short retention to save cost
}

variable "enable_ssm" {
  description = "Enable SSM for node management"
  type        = bool
  default     = true  # Dev: helpful for debugging
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

  # Dev: Cost-effective setup
  # - System nodes: t3.medium ON_DEMAND (cheap, burstable, reliable)
  # - Workload nodes: t3.medium SPOT (60-70% cheaper than on-demand)
  default = {
    system = {
      desired_size   = 2
      max_size       = 3
      min_size       = 1
      instance_types = ["t3.medium"]
      capacity_type  = "ON_DEMAND"
      disk_size      = 30
      labels = {
        "workload-type" = "system"
      }
    }
    spot = {
      desired_size   = 1
      max_size       = 5
      min_size       = 0
      instance_types = ["t3.medium", "t3a.medium", "t3.large", "t3a.large"]  # Diversify for spot availability
      capacity_type  = "SPOT"
      disk_size      = 30
      labels = {
        "workload-type" = "spot"
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

variable "autoscaler_scale_down_utilization_threshold" {
  description = "Node utilization threshold for scale down"
  type        = string
  default     = "0.5"
}
