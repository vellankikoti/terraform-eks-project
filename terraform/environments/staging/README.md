# Staging Environment

Intermediate configuration between dev and prod. Used for pre-production testing and validation.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Staging VPC                               │
│                    10.1.0.0/16                               │
│                                                               │
│  ┌──────────────┐  ┌──────────────┐                        │
│  │   AZ-1a       │  │   AZ-1b       │                        │
│  │               │  │               │                        │
│  │ Public Subnet │  │ Public Subnet │                        │
│  │ [NAT GW]      │  │ [NAT GW]      │                        │
│  │               │  │               │                        │
│  │ Private Subnet│  │ Private Subnet│                        │
│  │ [EKS Nodes]   │  │ [EKS Nodes]   │                        │
│  │ [Pods]        │  │ [Pods]        │                        │
│  └──────────────┘  └──────────────┘                        │
│                                                               │
│            ┌─────────────────────────────┐                  │
│            │   EKS Control Plane          │                  │
│            │   (AWS Managed)              │                  │
│            │   - All Logging Enabled       │                  │
│            └─────────────────────────────┘                  │
└─────────────────────────────────────────────────────────────┘
```

### Key Features

- **VPC**: 10.1.0.0/16 with 2 AZs (cost-optimized)
- **EKS**: Kubernetes 1.28 with production-like configuration
- **Node Groups**: 2 t3.large nodes (auto-scales 2-5)
- **NAT Gateways**: 2 NAT Gateways (one per AZ)
- **Add-ons**: All essential add-ons with HA configuration
- **Logging**: All control plane logs enabled, 14-day retention
- **Security**: Similar to production but with relaxed access controls

## Prerequisites

1. AWS CLI configured
2. Terraform >= 1.6.0
3. kubectl
4. helm
5. S3 bucket and DynamoDB table for Terraform state (configure in `backend.tf`)

## Estimated Monthly Cost

| Resource | Quantity | Unit Cost | Monthly Cost |
|----------|----------|-----------|--------------|
| EKS Control Plane | 1 | $73 | $73 |
| EC2 t3.large | 2-5 | $60 | $120-$300 |
| NAT Gateway | 2 | $35 | $70 |
| NAT Data Transfer | ~200GB | $0.045/GB | $9 |
| EBS gp3 (50GB) | 2-5 | $4 | $8-$20 |
| VPC Flow Logs | ~50GB | $0.50/GB | $25 |
| CloudWatch Logs | ~20GB | $0.50/GB | $10 |
| **Total** | | | **~$315-$507/month** |

**Cost Optimization:**
- Use Spot instances for non-critical workloads (-70%)
- Single NAT Gateway option (less HA, -50%)
- Smaller instance types if needed
- Destroy environment when not in use

## Configuration

### 1. Configure Backend

Edit `backend.tf` and uncomment the backend configuration:

```hcl
terraform {
  backend "s3" {
    bucket         = "myapp-terraform-state"
    key            = "staging/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-locks"
    encrypt        = true
  }
}
```

### 2. Configure Variables

Copy `terraform.tfvars.example` to `terraform.tfvars` and customize:

```bash
cp terraform.tfvars.example terraform.tfvars
```

### 3. Initialize Terraform

```bash
cd terraform/environments/staging
terraform init
```

### 4. Plan

```bash
terraform plan
```

Review the plan. You should see:
- VPC with 2 AZs
- 2 NAT Gateways
- EKS cluster
- 2 node groups
- All add-ons

### 5. Apply

```bash
terraform apply
```

This takes ~15-20 minutes.

### 6. Configure kubectl

```bash
aws eks update-kubeconfig --region us-east-1 --name myapp-staging
```

### 7. Verify

```bash
# Check nodes
kubectl get nodes

# Check all pods
kubectl get pods -A

# Check add-ons
kubectl get pods -n kube-system
```

You should see:
- 2 nodes in Ready state
- All add-ons running
- CoreDNS, AWS Load Balancer Controller, Cluster Autoscaler, EBS CSI Driver, Metrics Server

## Testing Workloads

Staging is perfect for:
- Testing application deployments
- Validating infrastructure changes
- Performance testing
- Security testing
- Integration testing

### Example: Deploy Test Application

```bash
# Deploy a test application
kubectl create deployment test-app --image=nginx
kubectl expose deployment test-app --port=80 --type=LoadBalancer

# Check LoadBalancer
kubectl get svc test-app
```

### Example: Test Ingress

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: test-ingress
  annotations:
    alb.ingress.kubernetes.io/scheme: internet-facing
spec:
  ingressClassName: alb
  rules:
  - host: test.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: test-app
            port:
              number: 80
```

## Monitoring & Logging

### CloudWatch Logs

All control plane logs are sent to CloudWatch:

```bash
# View API server logs
aws logs tail /aws/eks/myapp-staging/cluster --follow
```

### Metrics

Metrics Server is deployed for HPA/VPA:

```bash
# Check node metrics
kubectl top nodes

# Check pod metrics
kubectl top pods --all-namespaces
```

## Differences from Production

| Feature | Staging | Production |
|---------|---------|------------|
| AZs | 2 | 3+ |
| NAT Gateways | 2 | 3+ |
| Instance Type | t3.large | m5.large |
| Min Nodes | 2 | 3 |
| Log Retention | 14 days | 30 days |
| Database Subnets | Optional | Required |
| ECR Endpoints | Optional | Required |
| Public Access | Open | Restricted |

## Troubleshooting

### Cluster Not Accessible

If you can't access the cluster:

1. Verify security groups allow your IP
2. Check endpoint configuration
3. Verify IAM permissions

### Nodes Not Joining

If nodes aren't joining:

1. Check node IAM role has correct policies
2. Verify security groups allow communication
3. Check CloudWatch logs for errors
4. Use SSM to access nodes: `aws ssm start-session --target <instance-id>`

### Add-ons Not Working

If add-ons fail:

1. Check pod logs: `kubectl logs -n kube-system <pod-name>`
2. Verify IRSA is configured correctly
3. Check IAM role permissions

## Cleanup

**⚠️ WARNING: This will destroy all staging infrastructure!**

```bash
terraform destroy
```

**Before destroying:**
- Backup any test data
- Export any needed configurations
- Verify no critical workloads are running

## Support

For issues or questions:
1. Check the main [README.md](../../../README.md)
2. Review [Getting Started Guide](../../../GETTING_STARTED.md)
3. Check module documentation in `../../modules/`

## Next Steps

After deploying:
1. Deploy test applications
2. Validate infrastructure changes
3. Test monitoring and alerting
4. Validate backup procedures
5. Test disaster recovery procedures
