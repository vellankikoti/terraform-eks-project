###################
# VPC Outputs
###################

output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "vpc_cidr" {
  description = "VPC CIDR block"
  value       = module.vpc.vpc_cidr
}

output "private_subnet_ids" {
  description = "Private subnet IDs"
  value       = module.vpc.private_subnet_ids
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = module.vpc.public_subnet_ids
}

###################
# EKS Outputs
###################

output "cluster_id" {
  description = "EKS cluster ID"
  value       = module.eks.cluster_id
}

output "cluster_endpoint" {
  description = "EKS cluster endpoint"
  value       = module.eks.cluster_endpoint
}

output "cluster_version" {
  description = "EKS cluster version"
  value       = module.eks.cluster_version
}

output "cluster_security_group_id" {
  description = "EKS cluster security group ID"
  value       = module.eks.cluster_security_group_id
}

output "node_security_group_id" {
  description = "EKS node security group ID"
  value       = module.eks.node_security_group_id
}

output "oidc_provider_arn" {
  description = "OIDC provider ARN for IRSA"
  value       = module.eks.oidc_provider_arn
}

output "kubeconfig_command" {
  description = "Command to update kubeconfig"
  value       = module.eks.kubeconfig_command
}

###################
# Add-on Outputs
###################

output "alb_controller_role_arn" {
  description = "AWS Load Balancer Controller IAM role ARN"
  value       = module.aws_load_balancer_controller.iam_role_arn
}

output "cluster_autoscaler_role_arn" {
  description = "Cluster Autoscaler IAM role ARN"
  value       = module.cluster_autoscaler.iam_role_arn
}

output "ebs_csi_driver_role_arn" {
  description = "EBS CSI Driver IAM role ARN"
  value       = module.ebs_csi_driver.iam_role_arn
}

output "efs_csi_driver_role_arn" {
  description = "EFS CSI Driver IAM role ARN"
  value       = module.efs_csi_driver.iam_role_arn
}

output "external_dns_role_arn" {
  description = "External DNS IAM role ARN"
  value       = module.external_dns.iam_role_arn
}
