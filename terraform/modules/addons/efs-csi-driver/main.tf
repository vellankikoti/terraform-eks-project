# EFS CSI Driver Add-on
# Provides persistent volumes using Amazon EFS (shared network storage)
# Uses EKS-managed add-on for better lifecycle management

###################
# IAM Role for Service Account (IRSA)
###################

resource "aws_iam_role" "this" {
  name = "${var.cluster_name}-efs-csi-driver"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = var.oidc_provider_arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${var.oidc_provider_url}:sub" = "system:serviceaccount:${var.namespace}:${var.service_account_name}"
            "${var.oidc_provider_url}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = var.tags
}

###################
# IAM Policy (AWS Managed Policy)
###################

resource "aws_iam_role_policy_attachment" "this" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEFSCSIDriverPolicy"
  role       = aws_iam_role.this.name
}

###################
# EKS Add-on
###################

resource "aws_eks_addon" "this" {
  cluster_name             = var.cluster_name
  addon_name               = "aws-efs-csi-driver"
  addon_version            = var.addon_version
  service_account_role_arn = aws_iam_role.this.arn

  # Configuration values for the add-on
  configuration_values = var.configuration_values != null ? jsonencode(var.configuration_values) : null

  # Resolve conflicts by overwriting local values
  resolve_conflicts_on_update = var.resolve_conflicts_on_update
  resolve_conflicts_on_create = var.resolve_conflicts_on_create

  tags = var.tags

  depends_on = [
    aws_iam_role_policy_attachment.this
  ]
}
