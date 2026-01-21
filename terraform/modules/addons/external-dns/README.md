# External DNS Add-on Module

This module deploys External DNS using Helm. External DNS automatically creates and manages DNS records in Route53 based on Kubernetes Ingress and Service resources, eliminating the need to manually create DNS records.

## Features

- ✅ Helm-based deployment (easy updates)
- ✅ IRSA (IAM Roles for Service Accounts) for secure Route53 access
- ✅ Supports Ingress and Service resources
- ✅ Automatic DNS record creation and cleanup
- ✅ Domain filtering (only manage specific domains)
- ✅ TXT record ownership (prevents conflicts)
- ✅ Production-ready resource limits

## What It Does

External DNS:
- Watches Kubernetes Ingress and Service resources
- Creates Route53 A/AAAA records based on annotations
- Automatically deletes DNS records when resources are deleted
- Supports both public and private hosted zones
- Creates TXT records for ownership tracking

## Usage

```hcl
module "external_dns" {
  source = "../../modules/addons/external-dns"

  cluster_name       = module.eks.cluster_id
  aws_region         = var.aws_region
  oidc_provider_arn  = module.eks.oidc_provider_arn
  oidc_provider_url  = module.eks.oidc_provider_url

  # Route53 hosted zone IDs to manage
  route53_zone_ids = [
    "Z1234567890ABC",  # example.com
    "Z0987654321XYZ"   # app.example.com
  ]

  # Only manage specific domains
  domain_filters = [
    "example.com",
    "app.example.com"
  ]

  tags = {
    Environment = "production"
  }

  depends_on = [module.eks]
}
```

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.6.0 |
| helm | ~> 2.11 |
| aws | Route53 hosted zones configured |
| eks | EKS cluster with OIDC provider enabled |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| cluster_name | Name of the EKS cluster | `string` | n/a | yes |
| aws_region | AWS region | `string` | n/a | yes |
| oidc_provider_arn | ARN of the OIDC provider | `string` | n/a | yes |
| oidc_provider_url | URL of the OIDC provider | `string` | n/a | yes |
| route53_zone_ids | List of Route53 hosted zone IDs | `list(string)` | n/a | yes |
| namespace | Kubernetes namespace | `string` | `"kube-system"` | no |
| service_account_name | Service account name | `string` | `"external-dns"` | no |
| chart_version | Helm chart version | `string` | `"6.14.2"` | no |
| zone_type | Route53 zone type | `string` | `"public"` | no |
| domain_filters | List of domains to filter | `list(string)` | `[]` | no |
| txt_owner_id | TXT record owner ID | `string` | `null` | no |
| policy | DNS record policy | `string` | `"sync"` | no |
| sources | Sources to watch | `list(string)` | `["ingress", "service"]` | no |
| replica_count | Number of replicas | `number` | `2` | no |
| resources_limits_cpu | CPU limit | `string` | `"100m"` | no |
| resources_limits_memory | Memory limit | `string` | `"128Mi"` | no |
| resources_requests_cpu | CPU request | `string` | `"50m"` | no |
| resources_requests_memory | Memory request | `string` | `"64Mi"` | no |
| log_level | Log level | `string` | `"info"` | no |
| log_format | Log format | `string` | `"text"` | no |
| tags | Additional tags | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| iam_role_arn | ARN of the IAM role |
| iam_role_name | Name of the IAM role |
| service_account_name | Service account name |
| namespace | Kubernetes namespace |

## Cost Implications

**No additional cost** - External DNS runs on existing nodes and consumes minimal resources (~50m CPU, 64Mi memory per replica).

**Route53 costs:**
- Hosted zone: $0.50/month per zone
- Standard queries: $0.40 per million queries
- Alias queries: Free

## Example: Using with Ingress

Create an Ingress with External DNS annotation:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-app-ingress
  annotations:
    external-dns.alpha.kubernetes.io/hostname: myapp.example.com
    cert-manager.io/cluster-issuer: letsencrypt-prod
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - myapp.example.com
    secretName: my-app-tls
  rules:
  - host: myapp.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: my-app
            port:
              number: 80
```

External DNS will automatically create:
- A record: `myapp.example.com` → ALB IP
- TXT record: `myapp.example.com` → ownership info

## Example: Using with Service (LoadBalancer)

```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-app-service
  annotations:
    external-dns.alpha.kubernetes.io/hostname: api.example.com
spec:
  type: LoadBalancer
  ports:
  - port: 80
    targetPort: 8080
  selector:
    app: my-app
```

## Security

- ✅ Uses IRSA (no AWS credentials in pods)
- ✅ Least privilege IAM policy (only specified hosted zones)
- ✅ Domain filtering (only manages specified domains)
- ✅ TXT ownership tracking (prevents conflicts)

## Troubleshooting

**DNS records not created:**
- Check External DNS pods: `kubectl get pods -n kube-system -l app.kubernetes.io/name=external-dns`
- Check logs: `kubectl logs -n kube-system -l app.kubernetes.io/name=external-dns`
- Verify IAM permissions for Route53
- Check domain filters match your domains
- Verify Route53 zone IDs are correct

**DNS records not deleted:**
- Check policy setting (sync vs upsert-only)
- Verify TXT ownership records
- Check for multiple External DNS instances managing same zones

**Permission errors:**
- Verify IAM role has permissions for specified hosted zones
- Check OIDC provider is correctly configured
- Verify service account annotation is set

## References

- [External DNS GitHub](https://github.com/kubernetes-sigs/external-dns)
- [External DNS Helm Chart](https://github.com/kubernetes-sigs/external-dns/tree/master/charts/external-dns)
- [Route53 Pricing](https://aws.amazon.com/route53/pricing/)
