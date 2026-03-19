# Fluent Bit - Lightweight log processor and forwarder
# Runs as DaemonSet on every node, collects container and system logs,
# forwards to CloudWatch Logs (default), S3, or Elasticsearch

###################
# IAM Role (IRSA)
###################

resource "aws_iam_role" "fluent_bit" {
  name = "${var.cluster_name}-fluent-bit"

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
            "${var.oidc_provider_url}:aud" = "sts.amazonaws.com"
            "${var.oidc_provider_url}:sub" = "system:serviceaccount:${var.namespace}:${var.service_account_name}"
          }
        }
      }
    ]
  })

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-fluent-bit"
  })
}

resource "aws_iam_role_policy" "fluent_bit" {
  name = "${var.cluster_name}-fluent-bit"
  role = aws_iam_role.fluent_bit.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      # CloudWatch Logs permissions (always needed)
      [
        {
          Effect = "Allow"
          Action = [
            "logs:CreateLogGroup",
            "logs:CreateLogStream",
            "logs:PutLogEvents",
            "logs:DescribeLogGroups",
            "logs:DescribeLogStreams",
            "logs:PutRetentionPolicy"
          ]
          Resource = "*"
        }
      ],
      # S3 permissions (optional)
      var.enable_s3_output ? [
        {
          Effect = "Allow"
          Action = [
            "s3:PutObject",
            "s3:GetBucketLocation"
          ]
          Resource = [
            "arn:aws:s3:::${var.s3_bucket_name}",
            "arn:aws:s3:::${var.s3_bucket_name}/*"
          ]
        }
      ] : []
    )
  })
}

###################
# Helm Release
###################

resource "helm_release" "fluent_bit" {
  name       = "fluent-bit"
  repository = "https://fluent.github.io/helm-charts"
  chart      = "fluent-bit"
  version    = var.chart_version
  namespace  = var.namespace

  create_namespace = true

  # Service account with IRSA
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
    value = aws_iam_role.fluent_bit.arn
  }

  # Resources
  set {
    name  = "resources.requests.cpu"
    value = var.resources_requests_cpu
  }

  set {
    name  = "resources.requests.memory"
    value = var.resources_requests_memory
  }

  set {
    name  = "resources.limits.cpu"
    value = var.resources_limits_cpu
  }

  set {
    name  = "resources.limits.memory"
    value = var.resources_limits_memory
  }

  # Tolerations to run on all nodes
  set {
    name  = "tolerations[0].operator"
    value = "Exists"
  }

  # CloudWatch output configuration
  values = [yamlencode({
    config = {
      outputs = <<-EOT
        [OUTPUT]
            Name              cloudwatch_logs
            Match             *
            region            ${var.aws_region}
            log_group_name    ${var.cloudwatch_log_group_name}
            log_stream_prefix fluent-bit-
            auto_create_group true
            log_retention_days ${var.cloudwatch_log_retention_days}
      EOT
      filters = <<-EOT
        [FILTER]
            Name                kubernetes
            Match               kube.*
            Merge_Log           On
            Keep_Log            Off
            K8S-Logging.Parser  On
            K8S-Logging.Exclude On

        [FILTER]
            Name          multiline
            Match         kube.*
            multiline.key_content log
            multiline.parser java,python
      EOT
    }
  })]
}
