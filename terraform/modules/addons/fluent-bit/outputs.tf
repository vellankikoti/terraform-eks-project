output "iam_role_arn" {
  description = "Fluent Bit IAM role ARN"
  value       = aws_iam_role.fluent_bit.arn
}

output "namespace" {
  description = "Kubernetes namespace"
  value       = var.namespace
}

output "release_name" {
  description = "Helm release name"
  value       = helm_release.fluent_bit.name
}
