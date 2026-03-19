output "admin_role_arn" {
  description = "ARN of the admin IAM role"
  value       = length(var.admin_arns) > 0 ? aws_iam_role.admin[0].arn : ""
}

output "admin_role_name" {
  description = "Name of the admin IAM role"
  value       = length(var.admin_arns) > 0 ? aws_iam_role.admin[0].name : ""
}

output "developer_role_arn" {
  description = "ARN of the developer IAM role"
  value       = length(var.developer_arns) > 0 ? aws_iam_role.developer[0].arn : ""
}

output "developer_role_name" {
  description = "Name of the developer IAM role"
  value       = length(var.developer_arns) > 0 ? aws_iam_role.developer[0].name : ""
}

output "cicd_role_arn" {
  description = "ARN of the CI/CD IAM role"
  value       = length(var.cicd_arns) > 0 ? aws_iam_role.cicd[0].arn : ""
}

output "cicd_role_name" {
  description = "Name of the CI/CD IAM role"
  value       = length(var.cicd_arns) > 0 ? aws_iam_role.cicd[0].name : ""
}
