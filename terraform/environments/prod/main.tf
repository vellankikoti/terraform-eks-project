# Production Environment
# Enterprise-grade EKS cluster with full security, observability, and reliability
#
# Architecture decisions:
# - 3 AZs for high availability (survives an entire AZ failure)
# - ON_DEMAND system nodes (never risk system component eviction)
# - SPOT workload nodes with diverse instance types (cost savings with resilience)
# - Full observability stack (Prometheus, Grafana, OTel, Fluent Bit)
# - All security features enabled (flow logs, ECR endpoints, KMS encryption)
# - External DNS + Cert-Manager for automated DNS and TLS
#
# Estimated monthly cost: ~$500-800
# - EKS control plane: $75
# - 3x m5.large ON_DEMAND: ~$210
# - Spot nodes (variable): ~$60-150
# - 3x NAT Gateway: ~$105
# - VPC endpoints, monitoring, logging: ~$50-80
# - EBS volumes, data transfer: ~$30-50

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

  # Production: All features enabled
  enable_nat_gateway       = true   # One per AZ for HA
  create_database_subnets  = true   # Isolated subnets for RDS/ElastiCache
  enable_flow_logs         = true   # Required for security monitoring and compliance
  enable_s3_endpoint       = true   # Free - reduces NAT GW costs
  enable_dynamodb_endpoint = true   # Free - reduces NAT GW costs for state locking
  enable_ecr_endpoints     = true   # Saves significant NAT GW data transfer costs

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

  # Production: Private access required, public access restricted
  endpoint_private_access = true
  endpoint_public_access  = var.endpoint_public_access
  public_access_cidrs     = var.public_access_cidrs

  # Production: All control plane logs, 30-day retention
  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
  log_retention_days        = var.log_retention_days

  enable_ssm = true  # Required for production node debugging

  node_groups = var.node_groups

  tags = local.tags
}

###################
# Core Add-ons (Required for cluster functionality)
###################

# AWS Load Balancer Controller - Manages ALB/NLB for Ingress
module "aws_load_balancer_controller" {
  source = "../../modules/addons/aws-load-balancer-controller"

  cluster_name      = module.eks.cluster_id
  vpc_id            = module.vpc.vpc_id
  aws_region        = var.aws_region
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url

  replica_count = 2  # HA: survives a single pod failure

  tags = local.tags

  depends_on = [module.eks]
}

# Cluster Autoscaler - Scales nodes based on pod demand
module "cluster_autoscaler" {
  source = "../../modules/addons/cluster-autoscaler"

  cluster_name      = module.eks.cluster_id
  aws_region        = var.aws_region
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url

  # Production: Conservative scaling to avoid disruption
  scale_down_enabled               = true
  scale_down_delay_after_add       = "15m"  # Wait longer before removing nodes
  scale_down_unneeded_time         = "15m"  # Nodes must be idle longer
  scale_down_utilization_threshold = "0.65" # Higher threshold = keep more headroom

  expander = "least-waste"  # Best packing efficiency

  tags = local.tags

  depends_on = [module.eks]
}

# EBS CSI Driver - Persistent volume support
module "ebs_csi_driver" {
  source = "../../modules/addons/ebs-csi-driver"

  cluster_name      = module.eks.cluster_id
  aws_region        = var.aws_region
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url

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

# Metrics Server - Required for HPA and VPA
module "metrics_server" {
  source = "../../modules/addons/metrics-server"

  cluster_name  = module.eks.cluster_id
  replica_count = 2

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
  policy           = "sync"  # Production: sync mode keeps DNS in desired state

  replica_count = 2

  tags = local.tags

  depends_on = [module.eks]
}

# Cert-Manager - Automated TLS certificates (Let's Encrypt)
module "cert_manager" {
  source = "../../modules/addons/cert-manager"

  cluster_name      = module.eks.cluster_id
  aws_region        = var.aws_region
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url

  enable_route53   = var.cert_manager_enable_route53
  route53_zone_ids = var.route53_zone_ids

  webhook_replica_count = 2  # HA for admission webhook

  tags = local.tags

  depends_on = [module.eks]
}

###################
# Observability Add-ons
###################

# Prometheus - Metrics collection and alerting
module "prometheus" {
  source = "../../modules/addons/prometheus"

  namespace                = "monitoring"
  prometheus_replica_count = 2  # HA Prometheus

  # Production: Grafana deployed separately for better control
  enable_builtin_grafana = false

  # Production: Adequate resources for scraping many targets
  prometheus_resources_requests_cpu    = "1000m"
  prometheus_resources_requests_memory = "2Gi"
  prometheus_resources_limits_cpu      = "2000m"
  prometheus_resources_limits_memory   = "4Gi"

  tags = local.tags

  depends_on = [module.eks]
}

# Grafana - Dashboards and visualization
module "grafana" {
  source = "../../modules/addons/grafana"

  namespace      = "monitoring"
  replica_count  = 2
  prometheus_url = "http://prometheus-kube-prometheus-prometheus.monitoring.svc.cluster.local:9090"

  # Production: Use external secret management for real deployments
  admin_user     = "admin"
  admin_password = var.grafana_admin_password

  tags = local.tags

  depends_on = [module.prometheus]
}

# OpenTelemetry Collector - Distributed tracing and metrics pipeline
module "otel_collector" {
  source = "../../modules/addons/otel-collector"

  namespace     = "observability"
  mode          = "deployment"
  replica_count = 2

  tags = local.tags

  depends_on = [module.eks]
}

###################
# Operations Add-ons
###################

# Reloader - Rolling restart on ConfigMap/Secret changes
module "reloader" {
  source = "../../modules/addons/reloader"

  namespace = "reloader"

  tags = local.tags

  depends_on = [module.eks]
}

# ArgoCD - GitOps continuous delivery
module "argocd" {
  source = "../../modules/addons/argocd"

  cluster_name      = module.eks.cluster_id
  aws_region        = var.aws_region
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url

  server_replica_count = 2
  enable_irsa          = var.argocd_enable_irsa

  tags = local.tags

  depends_on = [module.eks]
}
