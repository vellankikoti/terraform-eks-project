# External Secrets Operator Module

Syncs secrets from AWS Secrets Manager and SSM Parameter Store into Kubernetes Secrets.

## Why Use This

Kubernetes Secrets are base64-encoded, not encrypted. External Secrets Operator:
- Keeps secrets in AWS Secrets Manager (encrypted, audited, rotated)
- Auto-syncs changes into K8s Secrets
- Supports secret rotation without pod restarts (pair with Reloader)

## Usage

```hcl
module "external_secrets" {
  source = "../../modules/addons/external-secrets"

  cluster_name      = module.eks.cluster_id
  aws_region        = var.aws_region
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url

  depends_on = [module.eks]
}
```

Then create ExternalSecret resources:

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: my-app-secrets
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: aws-secrets-manager
    kind: ClusterSecretStore
  target:
    name: my-app-secrets
  data:
  - secretKey: DB_PASSWORD
    remoteRef:
      key: prod/myapp/database
      property: password
```

## Cost

- No additional AWS cost for the operator
- AWS Secrets Manager: $0.40/secret/month + $0.05 per 10,000 API calls
- SSM Parameter Store (Standard): Free for standard parameters
