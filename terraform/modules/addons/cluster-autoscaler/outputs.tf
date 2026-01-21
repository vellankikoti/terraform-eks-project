output "iam_role_arn" {
  description = "ARN of the IAM role for Cluster Autoscaler"
  value       = aws_iam_role.this.arn
}

output "iam_role_name" {
  description = "Name of the IAM role for Cluster Autoscaler"
  value       = aws_iam_role.this.name
}

output "service_account_name" {
  description = "Name of the Kubernetes service account"
  value       = var.service_account_name
}

output "namespace" {
  description = "Kubernetes namespace where the autoscaler is installed"
  value       = var.namespace
}
