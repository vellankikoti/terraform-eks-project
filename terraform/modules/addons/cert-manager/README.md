# Cert-Manager Add-on Module

This module deploys Cert-Manager using Helm. Cert-Manager automatically provisions and manages TLS certificates from Let's Encrypt and other certificate authorities, working seamlessly with External DNS for automatic certificate lifecycle management.

## Features

- ✅ Helm-based deployment (easy updates)
- ✅ IRSA (IAM Roles for Service Accounts) for Route53 DNS01 challenge
- ✅ Automatic certificate provisioning and renewal
- ✅ Support for Let's Encrypt (HTTP01 and DNS01)
- ✅ Support for other CAs (AWS Private CA, etc.)
- ✅ Production-ready resource limits
- ✅ Prometheus metrics support

## What It Does

Cert-Manager:
- Watches Certificate resources in Kubernetes
- Provisions TLS certificates from Let's Encrypt or other CAs
- Automatically renews certificates before expiration
- Supports HTTP01 and DNS01 challenge methods
- Stores certificates as Kubernetes Secrets

## Usage

```hcl
module "cert_manager" {
  source = "../../modules/addons/cert-manager"

  cluster_name       = module.eks.cluster_id
  aws_region         = var.aws_region
  oidc_provider_arn  = module.eks.oidc_provider_arn
  oidc_provider_url  = module.eks.oidc_provider_url

  # Enable Route53 DNS01 challenge
  enable_route53 = true
  route53_zone_ids = [
    "Z1234567890ABC",  # example.com
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
| aws | Route53 hosted zones (for DNS01) |
| eks | EKS cluster with OIDC provider enabled |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| cluster_name | Name of the EKS cluster | `string` | n/a | yes |
| aws_region | AWS region | `string` | n/a | yes |
| oidc_provider_arn | ARN of the OIDC provider | `string` | n/a | yes |
| oidc_provider_url | URL of the OIDC provider | `string` | n/a | yes |
| namespace | Kubernetes namespace | `string` | `"cert-manager"` | no |
| service_account_name | Service account name | `string` | `"cert-manager"` | no |
| chart_version | Helm chart version | `string` | `"v1.13.3"` | no |
| install_crds | Install Cert-Manager CRDs | `bool` | `true` | no |
| enable_route53 | Enable Route53 DNS01 challenge | `bool` | `true` | no |
| route53_zone_ids | Route53 hosted zone IDs | `list(string)` | `[]` | no |
| resources_limits_cpu | CPU limit | `string` | `"100m"` | no |
| resources_limits_memory | Memory limit | `string` | `"128Mi"` | no |
| resources_requests_cpu | CPU request | `string` | `"50m"` | no |
| resources_requests_memory | Memory request | `string` | `"64Mi"` | no |
| prometheus_enabled | Enable Prometheus metrics | `bool` | `true` | no |
| webhook_replica_count | Webhook replicas | `number` | `2` | no |
| startupapicheck_enabled | Enable startup API check | `bool` | `true` | no |
| tags | Additional tags | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| iam_role_arn | ARN of the IAM role |
| iam_role_name | Name of the IAM role |
| service_account_name | Service account name |
| namespace | Kubernetes namespace |

## Cost Implications

**No additional cost** - Cert-Manager runs on existing nodes and consumes minimal resources (~50m CPU, 64Mi memory).

**Let's Encrypt certificates:**
- Free (rate limits apply: 50 certs/week per domain)

**Route53 costs (for DNS01):**
- Hosted zone: $0.50/month per zone
- DNS queries: $0.40 per million queries

## Example: ClusterIssuer for Let's Encrypt

After deploying Cert-Manager, create a ClusterIssuer:

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: admin@example.com
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - dns01:
        route53:
          region: us-east-1
          # IAM role ARN from module output
          # role: arn:aws:iam::123456789012:role/my-cluster-cert-manager
```

## Example: Certificate Resource

Create a Certificate resource:

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: my-app-tls
  namespace: default
spec:
  secretName: my-app-tls
  issuerRef:
    name: letsencrypt-prod
    kind: ClusterIssuer
  dnsNames:
  - myapp.example.com
  - www.example.com
```

## Example: Using with Ingress

Cert-Manager automatically provisions certificates for Ingress resources:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-app-ingress
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - myapp.example.com
    secretName: my-app-tls  # Cert-Manager will create this
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

## Challenge Methods

**HTTP01 Challenge:**
- Requires public ingress
- Simpler setup (no Route53 permissions needed)
- Works with any ingress controller

**DNS01 Challenge:**
- Works with private ingresses
- Requires Route53 permissions (IRSA)
- More reliable (no ingress dependency)

## Security

- ✅ Uses IRSA (no AWS credentials in pods)
- ✅ Least privilege IAM policy (only specified hosted zones)
- ✅ Automatic certificate renewal
- ✅ Secure certificate storage (Kubernetes Secrets)

## Troubleshooting

**Certificates not issued:**
- Check Cert-Manager pods: `kubectl get pods -n cert-manager`
- Check Certificate status: `kubectl describe certificate <name>`
- Check CertificateRequest: `kubectl get certificaterequests`
- Check Challenge resources: `kubectl get challenges`

**DNS01 challenge fails:**
- Verify IAM permissions for Route53
- Check Route53 zone IDs are correct
- Verify OIDC provider is correctly configured
- Check logs: `kubectl logs -n cert-manager -l app.kubernetes.io/name=cert-manager`

**HTTP01 challenge fails:**
- Verify ingress is publicly accessible
- Check ingress controller is working
- Verify domain points to ingress IP
- Check Let's Encrypt rate limits

**Certificate renewal issues:**
- Cert-Manager automatically renews certificates 30 days before expiration
- Check Certificate status for renewal status
- Verify ClusterIssuer is still valid

## References

- [Cert-Manager GitHub](https://github.com/cert-manager/cert-manager)
- [Cert-Manager Helm Chart](https://github.com/cert-manager/cert-manager/tree/master/deploy/charts/cert-manager)
- [Let's Encrypt](https://letsencrypt.org/)
- [Cert-Manager Documentation](https://cert-manager.io/docs/)
