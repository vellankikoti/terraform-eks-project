variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "cluster_arn" {
  description = "ARN of the EKS cluster"
  type        = string
}

variable "node_role_arn" {
  description = "ARN of the EKS node IAM role (for aws-auth mapping)"
  type        = string
}

variable "admin_arns" {
  description = "List of IAM ARNs that can assume the admin role"
  type        = list(string)
  default     = []
}

variable "developer_arns" {
  description = "List of IAM ARNs that can assume the developer role"
  type        = list(string)
  default     = []
}

variable "cicd_arns" {
  description = "List of IAM ARNs that can assume the CI/CD role"
  type        = list(string)
  default     = []
}

variable "additional_role_mappings" {
  description = "Additional IAM role mappings for aws-auth ConfigMap"
  type = list(object({
    rolearn  = string
    username = string
    groups   = list(string)
  }))
  default = []
}

variable "additional_user_mappings" {
  description = "Additional IAM user mappings for aws-auth ConfigMap"
  type = list(object({
    userarn  = string
    username = string
    groups   = list(string)
  }))
  default = []
}

variable "tags" {
  description = "Additional tags for resources"
  type        = map(string)
  default     = {}
}
