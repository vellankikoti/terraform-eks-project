# Multi-Team RBAC Example
# Demonstrates Kubernetes RBAC for a multi-team setup with:
# - Namespace isolation per team
# - Role-based access control
# - Network policies to isolate team traffic
# - Resource quotas and limit ranges to prevent noisy neighbors
#
# Usage:
#   cd terraform/examples/multi-team-rbac
#   terraform init
#   terraform apply -var="cluster_name=myapp-dev"

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

data "aws_eks_cluster" "this" {
  name = var.cluster_name
}

data "aws_eks_cluster_auth" "this" {
  name = var.cluster_name
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.this.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    args        = ["eks", "get-token", "--cluster-name", var.cluster_name]
    command     = "aws"
  }
}

###########################
# Namespace per Team
# Each team gets an isolated namespace with labels for policy targeting
###########################

resource "kubernetes_namespace" "team" {
  for_each = var.teams

  metadata {
    name = each.key

    labels = {
      team       = each.key
      managed-by = "terraform"
      # This label is used by NetworkPolicy to allow/deny traffic
      "network-policy" = each.key
    }

    annotations = {
      "team-lead" = each.value.lead
      "purpose"   = each.value.description
    }
  }
}

###########################
# Role per Team
# Grants full access WITHIN the team's namespace only
# Teams can manage deployments, services, configmaps, secrets, pods, and jobs
###########################

resource "kubernetes_role" "team_admin" {
  for_each = var.teams

  metadata {
    name      = "${each.key}-admin"
    namespace = kubernetes_namespace.team[each.key].metadata[0].name
  }

  # Core workload resources
  rule {
    api_groups = ["", "apps", "batch"]
    resources = [
      "pods",
      "pods/log",
      "pods/exec",
      "pods/portforward",
      "deployments",
      "replicasets",
      "statefulsets",
      "daemonsets",
      "jobs",
      "cronjobs",
    ]
    verbs = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }

  # Services and networking
  rule {
    api_groups = ["", "networking.k8s.io"]
    resources = [
      "services",
      "endpoints",
      "ingresses",
    ]
    verbs = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }

  # Configuration resources
  rule {
    api_groups = [""]
    resources = [
      "configmaps",
      "secrets",
      "serviceaccounts",
    ]
    verbs = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }

  # Autoscaling
  rule {
    api_groups = ["autoscaling"]
    resources  = ["horizontalpodautoscalers"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }

  # Events (read-only for debugging)
  rule {
    api_groups = [""]
    resources  = ["events"]
    verbs      = ["get", "list", "watch"]
  }

  # PodDisruptionBudgets
  rule {
    api_groups = ["policy"]
    resources  = ["poddisruptionbudgets"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }
}

###########################
# RoleBinding per Team
# Binds the team admin role to a Kubernetes group
# The group name maps to IAM roles via aws-auth ConfigMap
###########################

resource "kubernetes_role_binding" "team_admin" {
  for_each = var.teams

  metadata {
    name      = "${each.key}-admin-binding"
    namespace = kubernetes_namespace.team[each.key].metadata[0].name
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role.team_admin[each.key].metadata[0].name
  }

  # Bind to a Kubernetes group (configured in aws-auth ConfigMap)
  subject {
    kind      = "Group"
    name      = "team-${each.key}"
    api_group = "rbac.authorization.k8s.io"
  }
}

###########################
# ClusterRole: Read-Only Access
# Allows viewing resources across ALL namespaces
# Useful for platform teams, on-call engineers, or dashboards
###########################

resource "kubernetes_cluster_role" "readonly" {
  metadata {
    name = "cluster-readonly"

    labels = {
      managed-by = "terraform"
    }
  }

  # Read-only access to common resources
  rule {
    api_groups = ["", "apps", "batch", "networking.k8s.io", "autoscaling"]
    resources = [
      "pods",
      "pods/log",
      "deployments",
      "replicasets",
      "statefulsets",
      "daemonsets",
      "jobs",
      "cronjobs",
      "services",
      "endpoints",
      "ingresses",
      "configmaps",
      "events",
      "namespaces",
      "nodes",
      "horizontalpodautoscalers",
    ]
    verbs = ["get", "list", "watch"]
  }

  # Read-only access to persistent volumes
  rule {
    api_groups = [""]
    resources = [
      "persistentvolumes",
      "persistentvolumeclaims",
    ]
    verbs = ["get", "list", "watch"]
  }

  # Read-only access to RBAC (useful for auditing)
  rule {
    api_groups = ["rbac.authorization.k8s.io"]
    resources = [
      "roles",
      "rolebindings",
      "clusterroles",
      "clusterrolebindings",
    ]
    verbs = ["get", "list", "watch"]
  }
}

resource "kubernetes_cluster_role_binding" "readonly" {
  metadata {
    name = "cluster-readonly-binding"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.readonly.metadata[0].name
  }

  subject {
    kind      = "Group"
    name      = "cluster-readonly"
    api_group = "rbac.authorization.k8s.io"
  }
}

###########################
# NetworkPolicy per Namespace
# Isolates network traffic so teams cannot access each other's services
# Only allows:
# - Ingress from the same namespace
# - Ingress from kube-system (for system components like CoreDNS)
# - All egress (pods can reach external services and DNS)
###########################

resource "kubernetes_network_policy" "team_isolation" {
  for_each = var.teams

  metadata {
    name      = "default-deny-with-exceptions"
    namespace = kubernetes_namespace.team[each.key].metadata[0].name
  }

  spec {
    pod_selector {}  # Applies to ALL pods in the namespace

    # Default deny all ingress, allow specific sources
    ingress {
      # Allow traffic from within the same namespace
      from {
        namespace_selector {
          match_labels = {
            "network-policy" = each.key
          }
        }
      }
      # Allow traffic from kube-system (CoreDNS, ingress controller, etc.)
      from {
        namespace_selector {
          match_labels = {
            "kubernetes.io/metadata.name" = "kube-system"
          }
        }
      }
    }

    # Allow all egress (DNS, external APIs, databases, etc.)
    egress {}

    policy_types = ["Ingress", "Egress"]
  }
}

###########################
# ResourceQuota per Namespace
# Prevents any single team from consuming too many cluster resources
# Adjust values based on team size and workload requirements
###########################

resource "kubernetes_resource_quota" "team" {
  for_each = var.teams

  metadata {
    name      = "${each.key}-quota"
    namespace = kubernetes_namespace.team[each.key].metadata[0].name
  }

  spec {
    hard = {
      # Compute limits
      "requests.cpu"    = each.value.quota.cpu_request
      "requests.memory" = each.value.quota.memory_request
      "limits.cpu"      = each.value.quota.cpu_limit
      "limits.memory"   = each.value.quota.memory_limit

      # Object count limits
      "pods"                   = each.value.quota.max_pods
      "services"               = each.value.quota.max_services
      "services.loadbalancers" = each.value.quota.max_load_balancers
      "persistentvolumeclaims" = each.value.quota.max_pvcs
      "secrets"                = each.value.quota.max_secrets
      "configmaps"             = each.value.quota.max_configmaps
    }
  }
}

###########################
# LimitRange per Namespace
# Sets default resource requests/limits for pods that don't specify them
# Ensures every pod has resource constraints (required when quotas are enabled)
###########################

resource "kubernetes_limit_range" "team" {
  for_each = var.teams

  metadata {
    name      = "${each.key}-limits"
    namespace = kubernetes_namespace.team[each.key].metadata[0].name
  }

  spec {
    # Default limits for containers that don't specify their own
    limit {
      type = "Container"

      default = {
        cpu    = "500m"
        memory = "512Mi"
      }

      default_request = {
        cpu    = "100m"
        memory = "128Mi"
      }

      # Maximum any single container can request
      max = {
        cpu    = "4"
        memory = "8Gi"
      }

      # Minimum any single container must request
      min = {
        cpu    = "50m"
        memory = "64Mi"
      }
    }

    # Limits for entire pods (sum of all containers)
    limit {
      type = "Pod"

      max = {
        cpu    = "8"
        memory = "16Gi"
      }
    }
  }
}
