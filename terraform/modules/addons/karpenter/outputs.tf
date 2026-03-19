output "iam_role_arn" {
  description = "Karpenter controller IAM role ARN"
  value       = aws_iam_role.karpenter.arn
}

output "iam_role_name" {
  description = "Karpenter controller IAM role name"
  value       = aws_iam_role.karpenter.name
}

output "instance_profile_name" {
  description = "Instance profile for Karpenter-launched nodes"
  value       = aws_iam_instance_profile.karpenter.name
}

output "sqs_queue_name" {
  description = "SQS queue name for spot interruption handling"
  value       = aws_sqs_queue.karpenter.name
}

output "sqs_queue_arn" {
  description = "SQS queue ARN"
  value       = aws_sqs_queue.karpenter.arn
}

output "namespace" {
  description = "Kubernetes namespace"
  value       = var.namespace
}
