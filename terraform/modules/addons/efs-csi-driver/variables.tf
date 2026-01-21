variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "oidc_provider_arn" {
  description = "ARN of the OIDC provider for the EKS cluster"
  type        = string
}

variable "oidc_provider_url" {
  description = "URL of the OIDC provider (without https://)"
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace for the EFS CSI Driver service account"
  type        = string
  default     = "kube-system"
}

variable "service_account_name" {
  description = "Name of the Kubernetes service account"
  type        = string
  default     = "efs-csi-controller-sa"
}

variable "addon_version" {
  description = "Version of the EFS CSI Driver add-on"
  type        = string
  default     = "v2.0.7-eksbuild.1"

  validation {
    condition     = can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+", var.addon_version))
    error_message = "Add-on version must be in format vX.Y.Z-eksbuild.N (e.g., v2.0.7-eksbuild.1)."
  }
}

variable "configuration_values" {
  description = "Configuration values for the EFS CSI Driver add-on (JSON string)"
  type        = map(any)
  default     = null
}

variable "resolve_conflicts_on_update" {
  description = "How to resolve conflicts when updating the add-on (OVERWRITE, NONE)"
  type        = string
  default     = "OVERWRITE"

  validation {
    condition     = contains(["OVERWRITE", "NONE"], var.resolve_conflicts_on_update)
    error_message = "resolve_conflicts_on_update must be either OVERWRITE or NONE."
  }
}

variable "resolve_conflicts_on_create" {
  description = "How to resolve conflicts when creating the add-on (OVERWRITE, NONE)"
  type        = string
  default     = "OVERWRITE"

  validation {
    condition     = contains(["OVERWRITE", "NONE"], var.resolve_conflicts_on_create)
    error_message = "resolve_conflicts_on_create must be either OVERWRITE or NONE."
  }
}

variable "tags" {
  description = "Additional tags for resources"
  type        = map(string)
  default     = {}
}
