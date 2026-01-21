# External DNS Add-on
# Automatically creates and manages DNS records in Route53 based on Kubernetes resources
# Supports Ingress and Service resources with annotations

###################
# IAM Role for Service Account (IRSA)
###################

resource "aws_iam_role" "this" {
  name = "${var.cluster_name}-external-dns"

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
# IAM Policy
###################

resource "aws_iam_policy" "this" {
  name        = "${var.cluster_name}-external-dns"
  description = "IAM policy for External DNS to manage Route53 records"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "route53:ChangeResourceRecordSets"
        ]
        Resource = [
          for zone_id in var.route53_zone_ids : "arn:aws:route53:::hostedzone/${zone_id}"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "route53:ListHostedZones",
          "route53:ListResourceRecordSets",
          "route53:ListTagsForResource"
        ]
        Resource = "*"
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "this" {
  policy_arn = aws_iam_policy.this.arn
  role       = aws_iam_role.this.name
}

###################
# Helm Release
###################

resource "helm_release" "this" {
  name       = "external-dns"
  repository = "https://kubernetes-sigs.github.io/external-dns/"
  chart      = "external-dns"
  namespace  = var.namespace
  version    = var.chart_version

  create_namespace = true

  set {
    name  = "provider"
    value = "aws"
  }

  set {
    name  = "aws.region"
    value = var.aws_region
  }

  set {
    name  = "aws.zoneType"
    value = var.zone_type
  }

  set {
    name  = "serviceAccount.create"
    value = "true"
  }

  set {
    name  = "serviceAccount.name"
    value = var.service_account_name
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.this.arn
  }

  # Domain filters (only manage specific domains)
  dynamic "set" {
    for_each = var.domain_filters
    content {
      name  = "domainFilters[${set.key}]"
      value = set.value
    }
  }

  # TXT owner ID (prevents conflicts with multiple External DNS instances)
  set {
    name  = "txtOwnerId"
    value = var.txt_owner_id != null ? var.txt_owner_id : var.cluster_name
  }

  # Policy (sync, upsert-only, create-only)
  set {
    name  = "policy"
    value = var.policy
  }

  # Sources (ingress, service, crd)
  dynamic "set" {
    for_each = var.sources
    content {
      name  = "sources[${set.key}]"
      value = set.value
    }
  }

  # Resource limits
  set {
    name  = "resources.limits.cpu"
    value = var.resources_limits_cpu
  }

  set {
    name  = "resources.limits.memory"
    value = var.resources_limits_memory
  }

  set {
    name  = "resources.requests.cpu"
    value = var.resources_requests_cpu
  }

  set {
    name  = "resources.requests.memory"
    value = var.resources_requests_memory
  }

  # Replica count
  set {
    name  = "replicaCount"
    value = var.replica_count
  }

  # Log level
  set {
    name  = "logLevel"
    value = var.log_level
  }

  # Log format
  set {
    name  = "logFormat"
    value = var.log_format
  }

  depends_on = [
    aws_iam_role_policy_attachment.this
  ]
}
