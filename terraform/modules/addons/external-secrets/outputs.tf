output "iam_role_arn" {
  description = "External Secrets Operator IAM role ARN"
  value       = aws_iam_role.external_secrets.arn
}

output "iam_role_name" {
  description = "External Secrets Operator IAM role name"
  value       = aws_iam_role.external_secrets.name
}

output "namespace" {
  description = "Kubernetes namespace"
  value       = var.namespace
}

output "release_name" {
  description = "Helm release name"
  value       = helm_release.external_secrets.name
}

output "service_account_name" {
  description = "Service account name"
  value       = var.service_account_name
}
