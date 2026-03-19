# Development Environment
# Cost-optimized EKS cluster with VPC and essential add-ons
# Uses smaller instances, spot nodes for non-critical workloads, minimal replicas
#
# Estimated monthly cost: ~$150-200 (destroy when not in use!)
# - EKS control plane: $75
# - 2x t3.medium ON_DEMAND: ~$60
# - 1x NAT Gateway: ~$35
# - CloudWatch logs, EBS: ~$10

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.11"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Environment = var.environment
      Project     = var.project_name
      ManagedBy   = "terraform"
    }
  }
}

# Configure Helm provider (requires EKS cluster to exist first)
provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_id]
      command     = "aws"
    }
  }
}

# Configure Kubernetes provider
provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_id]
    command     = "aws"
  }
}

locals {
  cluster_name = "${var.project_name}-${var.environment}"

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

###################
# VPC Module
###################

module "vpc" {
  source = "../../modules/vpc"

  name_prefix  = local.cluster_name
  vpc_cidr     = var.vpc_cidr
  az_count     = var.az_count
  cluster_name = local.cluster_name
  aws_region   = var.aws_region

  # Dev: Cost-optimized - single NAT GW would save more but we keep per-AZ for learning
  enable_nat_gateway       = var.enable_nat_gateway
  create_database_subnets  = var.create_database_subnets
  enable_flow_logs         = var.enable_flow_logs
  enable_s3_endpoint       = var.enable_s3_endpoint       # Free - always enable
  enable_dynamodb_endpoint = var.enable_dynamodb_endpoint  # Free - always enable
  enable_ecr_endpoints     = var.enable_ecr_endpoints      # Dev: disabled to save ~$14/month

  tags = local.tags
}

###################
# EKS Cluster Module
###################

module "eks" {
  source = "../../modules/eks"

  cluster_name    = local.cluster_name
  cluster_version = var.cluster_version

  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids
  public_subnet_ids  = module.vpc.public_subnet_ids

  endpoint_private_access = var.endpoint_private_access
  endpoint_public_access  = var.endpoint_public_access
  public_access_cidrs     = var.public_access_cidrs

  enabled_cluster_log_types = var.enabled_cluster_log_types
  log_retention_days        = var.log_retention_days

  enable_ssm = var.enable_ssm

  node_groups = var.node_groups

  tags = local.tags
}

###################
# Core Add-ons (Required for cluster functionality)
###################

# AWS Load Balancer Controller - Required for Ingress
module "aws_load_balancer_controller" {
  source = "../../modules/addons/aws-load-balancer-controller"

  cluster_name      = module.eks.cluster_id
  vpc_id            = module.vpc.vpc_id
  aws_region        = var.aws_region
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url

  replica_count = 1  # Dev: single replica to save resources

  tags = local.tags

  depends_on = [module.eks]
}

# Cluster Autoscaler - Required for node scaling
module "cluster_autoscaler" {
  source = "../../modules/addons/cluster-autoscaler"

  cluster_name      = module.eks.cluster_id
  aws_region        = var.aws_region
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url

  scale_down_enabled               = var.autoscaler_scale_down_enabled
  scale_down_delay_after_add       = "5m"  # Dev: faster scale down for testing
  scale_down_unneeded_time         = "5m"  # Dev: faster cleanup
  scale_down_utilization_threshold = var.autoscaler_scale_down_utilization_threshold

  tags = local.tags

  depends_on = [module.eks]
}

# EBS CSI Driver - Required for persistent volumes
module "ebs_csi_driver" {
  source = "../../modules/addons/ebs-csi-driver"

  cluster_name      = module.eks.cluster_id
  aws_region        = var.aws_region
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url

  tags = local.tags

  depends_on = [module.eks]
}

# Metrics Server - Required for HPA
module "metrics_server" {
  source = "../../modules/addons/metrics-server"

  cluster_name  = module.eks.cluster_id
  replica_count = 1  # Dev: single replica

  tags = local.tags

  depends_on = [module.eks]
}

###################
# Observability Add-ons
###################

# Prometheus - Metrics collection (kube-prometheus-stack)
module "prometheus" {
  source = "../../modules/addons/prometheus"

  namespace                = "monitoring"
  prometheus_replica_count = 1  # Dev: single replica
  enable_builtin_grafana   = true  # Dev: use built-in Grafana for simplicity

  # Dev: reduced resources
  prometheus_resources_requests_cpu    = "250m"
  prometheus_resources_requests_memory = "512Mi"
  prometheus_resources_limits_cpu      = "500m"
  prometheus_resources_limits_memory   = "1Gi"

  tags = local.tags

  depends_on = [module.eks]
}

###################
# DNS & TLS Add-ons
###################

# External DNS - Automatically manages Route53 records from K8s Ingress/Service
module "external_dns" {
  source = "../../modules/addons/external-dns"

  cluster_name      = module.eks.cluster_id
  aws_region        = var.aws_region
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url

  route53_zone_ids = var.route53_zone_ids
  domain_filters   = var.domain_filters
  policy           = "upsert-only"  # Dev: safer - never deletes DNS records

  replica_count = 1  # Dev: single replica

  tags = local.tags

  depends_on = [module.eks]
}

# Cert-Manager - TLS certificate automation
module "cert_manager" {
  source = "../../modules/addons/cert-manager"

  cluster_name      = module.eks.cluster_id
  aws_region        = var.aws_region
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url

  enable_route53   = var.cert_manager_enable_route53
  route53_zone_ids = var.route53_zone_ids

  webhook_replica_count = 1  # Dev: single replica

  tags = local.tags

  depends_on = [module.eks]
}

# EFS CSI Driver - Shared persistent volumes (ReadWriteMany)
module "efs_csi_driver" {
  source = "../../modules/addons/efs-csi-driver"

  cluster_name      = module.eks.cluster_id
  aws_region        = var.aws_region
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url

  tags = local.tags

  depends_on = [module.eks]
}

# OpenTelemetry Collector - Traces and metrics pipeline
module "otel_collector" {
  source = "../../modules/addons/otel-collector"

  namespace     = "observability"
  mode          = "deployment"
  replica_count = 1  # Dev: single replica

  tags = local.tags

  depends_on = [module.eks]
}

###################
# Operations Add-ons
###################

# Reloader - Auto-restart pods on ConfigMap/Secret changes
module "reloader" {
  source = "../../modules/addons/reloader"

  namespace = "reloader"

  tags = local.tags

  depends_on = [module.eks]
}

# Grafana - Dashboards and visualization (standalone, not built into Prometheus)
module "grafana" {
  source = "../../modules/addons/grafana"

  namespace      = "monitoring"
  replica_count  = 1  # Dev: single replica
  prometheus_url = "http://prometheus-kube-prometheus-prometheus.monitoring.svc.cluster.local:9090"

  admin_user     = "admin"
  admin_password = var.grafana_admin_password

  tags = local.tags

  depends_on = [module.prometheus]
}

# ArgoCD - GitOps continuous delivery
module "argocd" {
  source = "../../modules/addons/argocd"

  cluster_name      = module.eks.cluster_id
  aws_region        = var.aws_region
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url

  server_replica_count = 1  # Dev: single replica
  enable_irsa          = var.argocd_enable_irsa

  tags = local.tags

  depends_on = [module.eks]
}
