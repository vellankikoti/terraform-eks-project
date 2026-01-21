output "iam_role_arn" {
  description = "ARN of the IAM role for EBS CSI Driver"
  value       = aws_iam_role.this.arn
}

output "iam_role_name" {
  description = "Name of the IAM role for EBS CSI Driver"
  value       = aws_iam_role.this.name
}

output "addon_arn" {
  description = "ARN of the EBS CSI Driver add-on"
  value       = aws_eks_addon.this.arn
}

output "addon_version" {
  description = "Version of the EBS CSI Driver add-on"
  value       = aws_eks_addon.this.addon_version
}

output "service_account_name" {
  description = "Name of the Kubernetes service account"
  value       = var.service_account_name
}

output "namespace" {
  description = "Kubernetes namespace where the driver is installed"
  value       = var.namespace
}
