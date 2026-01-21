# Cert-Manager Add-on
# Automatically provisions and manages TLS certificates from Let's Encrypt and other CAs
# Works seamlessly with External DNS for automatic certificate management

###################
# IAM Role for Service Account (IRSA)
###################

resource "aws_iam_role" "this" {
  name = "${var.cluster_name}-cert-manager"

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
# IAM Policy for Route53 DNS01 Challenge
###################

resource "aws_iam_policy" "this" {
  count = var.enable_route53 ? 1 : 0

  name        = "${var.cluster_name}-cert-manager-route53"
  description = "IAM policy for Cert-Manager to manage Route53 records for DNS01 challenge"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "route53:GetChange"
        ]
        Resource = "arn:aws:route53:::change/*"
      },
      {
        Effect = "Allow"
        Action = [
          "route53:ChangeResourceRecordSets",
          "route53:ListResourceRecordSets"
        ]
        Resource = [
          for zone_id in var.route53_zone_ids : "arn:aws:route53:::hostedzone/${zone_id}"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "route53:ListHostedZonesByName"
        ]
        Resource = "*"
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "route53" {
  count = var.enable_route53 ? 1 : 0

  policy_arn = aws_iam_policy.this[0].arn
  role       = aws_iam_role.this.name
}

###################
# Helm Release
###################

resource "helm_release" "this" {
  name       = "cert-manager"
  repository = "https://charts.jetstack.io"
  chart      = "cert-manager"
  namespace  = var.namespace
  version    = var.chart_version

  create_namespace = true

  # Install CRDs (required for cert-manager)
  set {
    name  = "installCRDs"
    value = var.install_crds
  }

  # Service account configuration
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

  # Prometheus metrics
  set {
    name  = "prometheus.enabled"
    value = var.prometheus_enabled
  }

  set {
    name  = "prometheus.servicemonitor.enabled"
    value = var.prometheus_enabled
  }

  # Webhook configuration
  set {
    name  = "webhook.replicaCount"
    value = var.webhook_replica_count
  }

  # Startup API check
  set {
    name  = "startupapicheck.enabled"
    value = var.startupapicheck_enabled
  }

  depends_on = [
    aws_iam_role_policy_attachment.route53
  ]
}
