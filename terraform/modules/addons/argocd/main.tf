###################
# ArgoCD Add-on
# GitOps controller for managing Kubernetes workloads from Git
###################

###################
# IAM Role for Service Account (IRSA) - optional
# Only needed if ArgoCD needs to access AWS APIs directly (e.g., S3, ECR).
###################

resource "aws_iam_role" "this" {
  count = var.enable_irsa ? 1 : 0

  name = "${var.cluster_name}-argocd"

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

resource "aws_iam_policy" "this" {
  count = var.enable_irsa && length(var.iam_policy_json) > 0 ? 1 : 0

  name        = "${var.cluster_name}-argocd"
  description = "Optional IAM policy for ArgoCD (GitOps workflows that need AWS APIs)"

  policy = var.iam_policy_json

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "this" {
  count = var.enable_irsa && length(var.iam_policy_json) > 0 ? 1 : 0

  policy_arn = aws_iam_policy.this[0].arn
  role       = aws_iam_role.this[0].name
}

###################
# Helm Release
###################

resource "helm_release" "this" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  namespace  = var.namespace
  version    = var.chart_version

  create_namespace = true

  # Service account
  set {
    name  = "server.serviceAccount.create"
    value = "true"
  }

  set {
    name  = "server.serviceAccount.name"
    value = var.service_account_name
  }

  # IRSA annotation (only if enabled)
  dynamic "set" {
    for_each = var.enable_irsa ? [1] : []
    content {
      name  = "server.serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
      value = aws_iam_role.this[0].arn
    }
  }

  # Resource limits for ArgoCD server
  set {
    name  = "server.resources.limits.cpu"
    value = var.server_resources_limits_cpu
  }

  set {
    name  = "server.resources.limits.memory"
    value = var.server_resources_limits_memory
  }

  set {
    name  = "server.resources.requests.cpu"
    value = var.server_resources_requests_cpu
  }

  set {
    name  = "server.resources.requests.memory"
    value = var.server_resources_requests_memory
  }

  # Replica count for HA
  set {
    name  = "server.replicas"
    value = var.server_replica_count
  }

  # Enable ingress optionally
  set {
    name  = "server.ingress.enabled"
    value = var.ingress_enabled
  }

  dynamic "set" {
    for_each = var.ingress_enabled ? [1] : []
    content {
      name  = "server.ingress.ingressClassName"
      value = var.ingress_class_name
    }
  }

  dynamic "set" {
    for_each = var.ingress_enabled ? [1] : []
    content {
      name  = "server.ingress.hosts[0]"
      value = var.ingress_host
    }
  }

  tags = var.tags

  depends_on = [
    aws_iam_role_policy_attachment.this
  ]
}

