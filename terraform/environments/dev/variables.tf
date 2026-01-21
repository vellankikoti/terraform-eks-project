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
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "az_count" {
  description = "Number of availability zones"
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
  default     = false
}

variable "enable_flow_logs" {
  description = "Enable VPC Flow Logs"
  type        = bool
  default     = false
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
  description = "Enable ECR VPC endpoints"
  type        = bool
  default     = false
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
  default     = 7
}

variable "enable_ssm" {
  description = "Enable SSM for node management"
  type        = bool
  default     = false
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

  default = {
    general = {
      desired_size   = 2
      max_size       = 5
      min_size       = 1
      instance_types = ["t3.medium"]
      capacity_type  = "ON_DEMAND"
      disk_size      = 50
    }
  }
}

###################
# Add-on Variables
###################

variable "alb_controller_replica_count" {
  description = "Number of AWS Load Balancer Controller replicas"
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
