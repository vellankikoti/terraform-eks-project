# IAM Module - EKS access control via IAM roles and aws-auth ConfigMap
#
# This module creates:
# 1. Admin IAM role (full cluster access)
# 2. Developer IAM role (read-only namespace access)
# 3. CI/CD IAM role (for pipeline deployments)
# 4. aws-auth ConfigMap (maps IAM to K8s RBAC)

###################
# Admin Role
###################

resource "aws_iam_role" "admin" {
  count = length(var.admin_arns) > 0 ? 1 : 0

  name = "${var.cluster_name}-admin"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = var.admin_arns
        }
        Action = "sts:AssumeRole"
        Condition = {
          StringEquals = {
            "sts:ExternalId" = var.cluster_name
          }
        }
      }
    ]
  })

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-admin"
    Role = "eks-admin"
  })
}

resource "aws_iam_role_policy" "admin" {
  count = length(var.admin_arns) > 0 ? 1 : 0

  name = "${var.cluster_name}-admin-eks-access"
  role = aws_iam_role.admin[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "eks:DescribeCluster",
          "eks:ListClusters",
          "eks:AccessKubernetesApi"
        ]
        Resource = var.cluster_arn
      }
    ]
  })
}

###################
# Developer Role (Read-Only)
###################

resource "aws_iam_role" "developer" {
  count = length(var.developer_arns) > 0 ? 1 : 0

  name = "${var.cluster_name}-developer"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = var.developer_arns
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-developer"
    Role = "eks-developer"
  })
}

resource "aws_iam_role_policy" "developer" {
  count = length(var.developer_arns) > 0 ? 1 : 0

  name = "${var.cluster_name}-developer-eks-access"
  role = aws_iam_role.developer[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "eks:DescribeCluster",
          "eks:ListClusters"
        ]
        Resource = var.cluster_arn
      }
    ]
  })
}

###################
# CI/CD Role
###################

resource "aws_iam_role" "cicd" {
  count = length(var.cicd_arns) > 0 ? 1 : 0

  name = "${var.cluster_name}-cicd"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = var.cicd_arns
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-cicd"
    Role = "eks-cicd"
  })
}

resource "aws_iam_role_policy" "cicd" {
  count = length(var.cicd_arns) > 0 ? 1 : 0

  name = "${var.cluster_name}-cicd-eks-access"
  role = aws_iam_role.cicd[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "eks:DescribeCluster",
          "eks:ListClusters",
          "eks:AccessKubernetesApi"
        ]
        Resource = var.cluster_arn
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage"
        ]
        Resource = "*"
      }
    ]
  })
}

###################
# aws-auth ConfigMap
###################

resource "kubernetes_config_map_v1_data" "aws_auth" {
  metadata {
    name      = "aws-auth"
    namespace = "kube-system"
  }

  force = true

  data = {
    mapRoles = yamlencode(concat(
      # Node role mapping (required for nodes to join cluster)
      [
        {
          rolearn  = var.node_role_arn
          username = "system:node:{{EC2PrivateDNSName}}"
          groups   = ["system:bootstrappers", "system:nodes"]
        }
      ],
      # Admin role mapping
      length(var.admin_arns) > 0 ? [
        {
          rolearn  = aws_iam_role.admin[0].arn
          username = "admin:{{SessionName}}"
          groups   = ["system:masters"]
        }
      ] : [],
      # Developer role mapping
      length(var.developer_arns) > 0 ? [
        {
          rolearn  = aws_iam_role.developer[0].arn
          username = "developer:{{SessionName}}"
          groups   = ["eks-developer"]
        }
      ] : [],
      # CI/CD role mapping
      length(var.cicd_arns) > 0 ? [
        {
          rolearn  = aws_iam_role.cicd[0].arn
          username = "cicd:{{SessionName}}"
          groups   = ["eks-cicd"]
        }
      ] : [],
      # Additional custom role mappings
      var.additional_role_mappings
    ))

    mapUsers = yamlencode(var.additional_user_mappings)
  }
}

###################
# Kubernetes RBAC for Developer Role
###################

resource "kubernetes_cluster_role" "developer" {
  count = length(var.developer_arns) > 0 ? 1 : 0

  metadata {
    name = "eks-developer"
  }

  # Read-only access to most resources
  rule {
    api_groups = ["", "apps", "batch", "networking.k8s.io"]
    resources  = ["pods", "services", "deployments", "replicasets", "statefulsets", "daemonsets", "jobs", "cronjobs", "ingresses", "configmaps", "events", "namespaces", "nodes"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = [""]
    resources  = ["pods/log"]
    verbs      = ["get", "list"]
  }
}

resource "kubernetes_cluster_role_binding" "developer" {
  count = length(var.developer_arns) > 0 ? 1 : 0

  metadata {
    name = "eks-developer-binding"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.developer[0].metadata[0].name
  }

  subject {
    kind      = "Group"
    name      = "eks-developer"
    api_group = "rbac.authorization.k8s.io"
  }
}

###################
# Kubernetes RBAC for CI/CD Role
###################

resource "kubernetes_cluster_role" "cicd" {
  count = length(var.cicd_arns) > 0 ? 1 : 0

  metadata {
    name = "eks-cicd"
  }

  # Deploy access
  rule {
    api_groups = ["", "apps", "batch", "networking.k8s.io"]
    resources  = ["pods", "services", "deployments", "replicasets", "statefulsets", "daemonsets", "jobs", "cronjobs", "ingresses", "configmaps", "secrets", "serviceaccounts"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }

  rule {
    api_groups = [""]
    resources  = ["namespaces"]
    verbs      = ["get", "list", "watch"]
  }
}

resource "kubernetes_cluster_role_binding" "cicd" {
  count = length(var.cicd_arns) > 0 ? 1 : 0

  metadata {
    name = "eks-cicd-binding"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.cicd[0].metadata[0].name
  }

  subject {
    kind      = "Group"
    name      = "eks-cicd"
    api_group = "rbac.authorization.k8s.io"
  }
}
