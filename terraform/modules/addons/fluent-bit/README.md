# Fluent Bit Module

Lightweight log processor and forwarder. Runs as a DaemonSet collecting container logs from every node.

## Outputs

- CloudWatch Logs (default)
- S3 (optional, for archival)

## Usage

```hcl
module "fluent_bit" {
  source = "../../modules/addons/fluent-bit"

  cluster_name      = module.eks.cluster_id
  aws_region        = var.aws_region
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url

  cloudwatch_log_group_name     = "/eks/${local.cluster_name}/containers"
  cloudwatch_log_retention_days = 14

  depends_on = [module.eks]
}
```

## Cost

- CloudWatch Logs ingestion: $0.50/GB
- CloudWatch Logs storage: $0.03/GB/month
- Tip: Use S3 output for long-term archival ($0.023/GB/month)
