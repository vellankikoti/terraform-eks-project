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
  description = "CIDR block for VPC (prod uses 10.0.0.0/16 - primary range)"
  type        = string
  default     = "10.0.0.0/16"
}

variable "az_count" {
  description = "Number of availability zones (production: 3 minimum for HA)"
  type        = number
  default     = 3

  validation {
    condition     = var.az_count >= 3 && var.az_count <= 6
    error_message = "Production must use at least 3 AZs for high availability."
  }
}

###################
# EKS Variables
###################

variable "cluster_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.31"
}

variable "endpoint_public_access" {
  description = "Enable public API endpoint (production: restrict with CIDRs or disable)"
  type        = bool
  default     = true
}

variable "public_access_cidrs" {
  description = "CIDR blocks allowed to access public API endpoint (production: restrict to VPN/office IPs)"
  type        = list(string)
  default     = ["0.0.0.0/0"]  # IMPORTANT: Replace with actual office/VPN IPs before production use
}

variable "log_retention_days" {
  description = "CloudWatch log retention days (production: 30+ for compliance)"
  type        = number
  default     = 30
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

  # Production: Enterprise-grade node group strategy
  #
  # WHY this layout:
  # 1. "system" nodes (ON_DEMAND): Run critical infra (CoreDNS, kube-proxy, monitoring)
  #    - ON_DEMAND because system pods can't tolerate interruption
  #    - m5.large: 2 vCPU, 8 GiB RAM - good balance for system workloads
  #    - min_size=3 ensures one per AZ (survives AZ failure)
  #
  # 2. "general" nodes (ON_DEMAND): Run stateful or critical app workloads
  #    - For services that can't handle spot interruptions (databases, queues)
  #    - Scales based on demand
  #
  # 3. "spot" nodes (SPOT): Run stateless, interruptible workloads
  #    - 60-70% cheaper than on-demand
  #    - Multiple instance families for availability (t3, t3a, m5, m5a, m6i)
  #    - Applications must handle graceful termination (2-min warning)
  #    - PodDisruptionBudgets protect against mass eviction
  default = {
    system = {
      desired_size   = 3
      max_size       = 4
      min_size       = 3
      instance_types = ["m5.large"]
      capacity_type  = "ON_DEMAND"
      disk_size      = 100
      labels = {
        "workload-type" = "system"
        "node-role"     = "system"
      }
      taints = [{
        key    = "CriticalAddonsOnly"
        value  = "true"
        effect = "PREFER_NO_SCHEDULE"
      }]
    }
    general = {
      desired_size   = 2
      max_size       = 10
      min_size       = 2
      instance_types = ["m5.large", "m5a.large"]
      capacity_type  = "ON_DEMAND"
      disk_size      = 100
      labels = {
        "workload-type" = "general"
      }
    }
    spot = {
      desired_size   = 2
      max_size       = 20
      min_size       = 0
      instance_types = ["t3.large", "t3a.large", "m5.large", "m5a.large", "m6i.large", "m6a.large"]
      capacity_type  = "SPOT"
      disk_size      = 50
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

variable "grafana_admin_password" {
  description = "Grafana admin password (use secrets manager in real production)"
  type        = string
  default     = "changeme-use-external-secrets"
  sensitive   = true
}

variable "argocd_enable_irsa" {
  description = "Enable IRSA for ArgoCD (needed if ArgoCD manages AWS resources)"
  type        = bool
  default     = false
}

###################
# DNS & TLS Variables
###################

variable "route53_zone_ids" {
  description = "Route53 hosted zone IDs for External DNS and Cert-Manager"
  type        = list(string)
  default     = []  # Provide your zone IDs to enable DNS automation
}

variable "domain_filters" {
  description = "Domain filters for External DNS (e.g., ['example.com'])"
  type        = list(string)
  default     = []
}

variable "cert_manager_enable_route53" {
  description = "Enable Route53 for Cert-Manager DNS01 challenge"
  type        = bool
  default     = false  # Enable when Route53 zone IDs are provided
}
