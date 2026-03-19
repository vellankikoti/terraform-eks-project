variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "aws_region" {
  description = "AWS region where the EKS cluster is running"
  type        = string
  default     = "us-east-1"
}

variable "teams" {
  description = "Map of teams with their configuration, quotas, and metadata"
  type = map(object({
    lead        = string
    description = string
    quota = object({
      cpu_request        = string
      memory_request     = string
      cpu_limit          = string
      memory_limit       = string
      max_pods           = string
      max_services       = string
      max_load_balancers = string
      max_pvcs           = string
      max_secrets        = string
      max_configmaps     = string
    })
  }))

  default = {
    frontend = {
      lead        = "alice@example.com"
      description = "Frontend web applications"
      quota = {
        cpu_request        = "4"
        memory_request     = "8Gi"
        cpu_limit          = "8"
        memory_limit       = "16Gi"
        max_pods           = "20"
        max_services       = "10"
        max_load_balancers = "2"
        max_pvcs           = "5"
        max_secrets        = "20"
        max_configmaps     = "20"
      }
    }

    backend = {
      lead        = "bob@example.com"
      description = "Backend API services"
      quota = {
        cpu_request        = "8"
        memory_request     = "16Gi"
        cpu_limit          = "16"
        memory_limit       = "32Gi"
        max_pods           = "40"
        max_services       = "20"
        max_load_balancers = "2"
        max_pvcs           = "10"
        max_secrets        = "30"
        max_configmaps     = "30"
      }
    }

    data = {
      lead        = "carol@example.com"
      description = "Data processing and analytics"
      quota = {
        cpu_request        = "16"
        memory_request     = "32Gi"
        cpu_limit          = "32"
        memory_limit       = "64Gi"
        max_pods           = "30"
        max_services       = "10"
        max_load_balancers = "1"
        max_pvcs           = "20"
        max_secrets        = "20"
        max_configmaps     = "20"
      }
    }
  }
}
