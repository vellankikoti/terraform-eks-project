# Karpenter Module

Next-generation Kubernetes node autoscaler that provisions right-sized compute in seconds.

## Why Karpenter over Cluster Autoscaler

| Feature | Cluster Autoscaler | Karpenter |
|---------|-------------------|-----------|
| Provisioning speed | Minutes | Seconds |
| Instance selection | Pre-defined node groups | Any instance type |
| Spot handling | Basic | Native (SQS interruption queue) |
| Consolidation | No | Yes (replaces underutilized nodes) |
| Configuration | Node group per type | NodePool + EC2NodeClass |

## Architecture

```
Pod Pending --> Karpenter Controller --> EC2 Fleet API --> Node Ready
                     |
                     +--> SQS Queue <-- EventBridge <-- Spot Interruption
```

## Usage

```hcl
module "karpenter" {
  source = "../../modules/addons/karpenter"

  cluster_name     = module.eks.cluster_id
  cluster_endpoint = module.eks.cluster_endpoint
  cluster_arn      = module.eks.cluster_arn
  aws_region       = var.aws_region
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url
  node_role_arn     = module.eks.node_role_arn

  depends_on = [module.eks]
}
```

After deploying, create NodePool and EC2NodeClass resources via kubectl or Terraform kubernetes_manifest.

## Cost

- No additional AWS cost for Karpenter itself
- SQS queue: ~$0 (low volume)
- Typically saves 30-50% on compute costs through better bin-packing and spot usage
