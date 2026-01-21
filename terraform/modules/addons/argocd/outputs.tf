output "iam_role_arn" {
  description = "ARN of the IAM role for ArgoCD (if IRSA is enabled)"
  value       = try(aws_iam_role.this[0].arn, null)
}

output "service_account_name" {
  description = "Name of the Kubernetes service account for ArgoCD server"
  value       = var.service_account_name
}

output "namespace" {
  description = "Kubernetes namespace where ArgoCD is installed"
  value       = var.namespace
}

