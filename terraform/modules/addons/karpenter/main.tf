# Karpenter - Next-generation Kubernetes autoscaler
#
# Why Karpenter over Cluster Autoscaler:
# - Provisions nodes in seconds (vs minutes)
# - Understands spot interruptions natively
# - Consolidates underutilized nodes automatically
# - No node group management needed
# - Supports any instance type without pre-configuration

###################
# IAM Role for Karpenter Controller (IRSA)
###################

resource "aws_iam_role" "karpenter" {
  name = "${var.cluster_name}-karpenter"

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
    Name = "${var.cluster_name}-karpenter"
  })
}

resource "aws_iam_role_policy" "karpenter" {
  name = "${var.cluster_name}-karpenter"
  role = aws_iam_role.karpenter.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EC2Permissions"
        Effect = "Allow"
        Action = [
          "ec2:CreateLaunchTemplate",
          "ec2:CreateFleet",
          "ec2:RunInstances",
          "ec2:CreateTags",
          "ec2:TerminateInstances",
          "ec2:DeleteLaunchTemplate",
          "ec2:DescribeLaunchTemplates",
          "ec2:DescribeInstances",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeSubnets",
          "ec2:DescribeImages",
          "ec2:DescribeInstanceTypes",
          "ec2:DescribeInstanceTypeOfferings",
          "ec2:DescribeAvailabilityZones",
          "ec2:DescribeSpotPriceHistory"
        ]
        Resource = "*"
      },
      {
        Sid    = "PassRoleToNodes"
        Effect = "Allow"
        Action = "iam:PassRole"
        Resource = var.node_role_arn
      },
      {
        Sid    = "EKSAccess"
        Effect = "Allow"
        Action = [
          "eks:DescribeCluster"
        ]
        Resource = var.cluster_arn
      },
      {
        Sid    = "SSMAccess"
        Effect = "Allow"
        Action = [
          "ssm:GetParameter"
        ]
        Resource = "arn:aws:ssm:${var.aws_region}::parameter/aws/service/*"
      },
      {
        Sid    = "PricingAccess"
        Effect = "Allow"
        Action = [
          "pricing:GetProducts"
        ]
        Resource = "*"
      },
      {
        Sid    = "SQSAccess"
        Effect = "Allow"
        Action = [
          "sqs:DeleteMessage",
          "sqs:GetQueueUrl",
          "sqs:ReceiveMessage"
        ]
        Resource = aws_sqs_queue.karpenter.arn
      }
    ]
  })
}

###################
# Instance Profile for Karpenter-launched Nodes
###################

resource "aws_iam_instance_profile" "karpenter" {
  name = "${var.cluster_name}-karpenter-node"
  role = split("/", var.node_role_arn)[1]

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-karpenter-node"
  })
}

###################
# SQS Queue for Spot Interruption Handling
###################

resource "aws_sqs_queue" "karpenter" {
  name                      = "${var.cluster_name}-karpenter"
  message_retention_seconds = 300
  sqs_managed_sse_enabled   = true

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-karpenter"
  })
}

resource "aws_sqs_queue_policy" "karpenter" {
  queue_url = aws_sqs_queue.karpenter.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "EventBridgeAccess"
        Effect    = "Allow"
        Principal = { Service = "events.amazonaws.com" }
        Action    = "sqs:SendMessage"
        Resource  = aws_sqs_queue.karpenter.arn
      }
    ]
  })
}

###################
# EventBridge Rules for Spot Interruptions
###################

resource "aws_cloudwatch_event_rule" "spot_interruption" {
  name        = "${var.cluster_name}-karpenter-spot-interruption"
  description = "Spot instance interruption warning"

  event_pattern = jsonencode({
    source      = ["aws.ec2"]
    detail-type = ["EC2 Spot Instance Interruption Warning"]
  })

  tags = var.tags
}

resource "aws_cloudwatch_event_target" "spot_interruption" {
  rule      = aws_cloudwatch_event_rule.spot_interruption.name
  target_id = "karpenter"
  arn       = aws_sqs_queue.karpenter.arn
}

resource "aws_cloudwatch_event_rule" "rebalance" {
  name        = "${var.cluster_name}-karpenter-rebalance"
  description = "EC2 instance rebalance recommendation"

  event_pattern = jsonencode({
    source      = ["aws.ec2"]
    detail-type = ["EC2 Instance Rebalance Recommendation"]
  })

  tags = var.tags
}

resource "aws_cloudwatch_event_target" "rebalance" {
  rule      = aws_cloudwatch_event_rule.rebalance.name
  target_id = "karpenter"
  arn       = aws_sqs_queue.karpenter.arn
}

resource "aws_cloudwatch_event_rule" "instance_state_change" {
  name        = "${var.cluster_name}-karpenter-state-change"
  description = "EC2 instance state change"

  event_pattern = jsonencode({
    source      = ["aws.ec2"]
    detail-type = ["EC2 Instance State-change Notification"]
  })

  tags = var.tags
}

resource "aws_cloudwatch_event_target" "instance_state_change" {
  rule      = aws_cloudwatch_event_rule.instance_state_change.name
  target_id = "karpenter"
  arn       = aws_sqs_queue.karpenter.arn
}

###################
# Helm Release
###################

resource "helm_release" "karpenter" {
  name       = "karpenter"
  repository = "oci://public.ecr.aws/karpenter"
  chart      = "karpenter"
  version    = var.chart_version
  namespace  = var.namespace

  create_namespace = true

  set {
    name  = "settings.clusterName"
    value = var.cluster_name
  }

  set {
    name  = "settings.clusterEndpoint"
    value = var.cluster_endpoint
  }

  set {
    name  = "settings.interruptionQueue"
    value = aws_sqs_queue.karpenter.name
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.karpenter.arn
  }

  set {
    name  = "serviceAccount.name"
    value = var.service_account_name
  }

  set {
    name  = "replicas"
    value = var.replica_count
  }

  set {
    name  = "controller.resources.requests.cpu"
    value = var.resources_requests_cpu
  }

  set {
    name  = "controller.resources.requests.memory"
    value = var.resources_requests_memory
  }

  set {
    name  = "controller.resources.limits.cpu"
    value = var.resources_limits_cpu
  }

  set {
    name  = "controller.resources.limits.memory"
    value = var.resources_limits_memory
  }
}
