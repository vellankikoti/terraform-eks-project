# ArgoCD Add-on Module

This module deploys **ArgoCD** on EKS using Helm. ArgoCD provides GitOps workflows for continuously deploying applications from Git repositories to your Kubernetes cluster.

## Features

- ✅ Helm-based deployment (easy upgrades)
- ✅ Optional IRSA (IAM Roles for Service Accounts) when ArgoCD needs AWS API access
- ✅ Configurable replica count for HA
- ✅ Optional ALB ingress integration
- ✅ Production-ready resource limits

## What It Does

ArgoCD:

- Watches Git repositories for changes
- Applies Kubernetes manifests to the cluster
- Provides a web UI and CLI for managing applications
- Supports multi-environment GitOps workflows

## Usage

```hcl
module "argocd" {
  source = "../../modules/addons/argocd"

  cluster_name      = module.eks.cluster_id
  aws_region        = var.aws_region
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url

  # Optional: enable IRSA if ArgoCD needs AWS API access
  enable_irsa     = false
  iam_policy_json = "" # Provide JSON if needed

  # Optional: enable ingress
  ingress_enabled    = true
  ingress_class_name = "alb"
  ingress_host       = "argocd.example.com"

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }

  depends_on = [module.eks]
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| cluster_name | EKS cluster name | `string` | n/a | yes |
| aws_region | AWS region | `string` | n/a | yes |
| oidc_provider_arn | OIDC provider ARN | `string` | n/a | yes |
| oidc_provider_url | OIDC provider URL (no https://) | `string` | n/a | yes |
| namespace | Kubernetes namespace | `string` | `"argocd"` | no |
| service_account_name | ArgoCD server service account | `string` | `"argocd-server"` | no |
| chart_version | ArgoCD chart version | `string` | `"5.51.6"` | no |
| enable_irsa | Enable IRSA for ArgoCD | `bool` | `false` | no |
| iam_policy_json | Optional IAM policy JSON | `string` | `""` | no |
| server_replica_count | ArgoCD server replicas | `number` | `2` | no |
| server_resources_limits_cpu | CPU limit | `string` | `"500m"` | no |
| server_resources_limits_memory | Memory limit | `string` | `"512Mi"` | no |
| server_resources_requests_cpu | CPU request | `string` | `"250m"` | no |
| server_resources_requests_memory | Memory request | `string` | `"256Mi"` | no |
| ingress_enabled | Enable ingress | `bool` | `false` | no |
| ingress_class_name | Ingress class name | `string` | `"alb"` | no |
| ingress_host | ArgoCD host | `string` | `"argocd.example.com"` | no |
| tags | Additional tags | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| iam_role_arn | IAM role ARN (if IRSA enabled) |
| service_account_name | ArgoCD service account name |
| namespace | Namespace where ArgoCD is installed |

## Cost

ArgoCD itself has **no direct AWS cost**. You pay for:

- EC2 nodes that run ArgoCD pods
- Network traffic for Git and API calls

Typical resource usage is small (a few hundred millicores CPU, a few hundred MiB memory).

## Verification

After deployment:

```bash
kubectl get pods -n argocd
kubectl get svc -n argocd
```

If ingress is enabled:

1. Wait for ALB to be provisioned
2. Access `https://argocd.example.com` (or your configured host)

## Security Notes

- Use IRSA only if ArgoCD needs AWS access (e.g., S3 manifests, ECR images)
- Restrict ingress access with WAF / security groups
- Use SSO / RBAC for ArgoCD login

