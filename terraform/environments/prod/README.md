# Production Environment

Production-hardened EKS cluster with high availability, security, and monitoring.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Production VPC                             │
│                    10.0.0.0/16                                │
│                                                               │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐       │
│  │   AZ-1a       │  │   AZ-1b       │  │   AZ-1c       │       │
│  │               │  │               │  │               │       │
│  │ Public Subnet │  │ Public Subnet │  │ Public Subnet │       │
│  │ [NAT GW]      │  │ [NAT GW]      │  │ [NAT GW]      │       │
│  │               │  │               │  │               │       │
│  │ Private Subnet│  │ Private Subnet│  │ Private Subnet│       │
│  │ [EKS Nodes]   │  │ [EKS Nodes]   │  │ [EKS Nodes]   │       │
│  │ [Pods]        │  │ [Pods]        │  │ [Pods]        │       │
│  └──────────────┘  └──────────────┘  └──────────────┘       │
│                                                               │
│            ┌─────────────────────────────┐                  │
│            │   EKS Control Plane          │                  │
│            │   (AWS Managed)              │                  │
│            │   - Private Endpoint          │                  │
│            │   - All Logging Enabled       │                  │
│            │   - KMS Encryption            │                  │
│            └─────────────────────────────┘                  │
└─────────────────────────────────────────────────────────────┘
```

### Key Features

- **VPC**: 10.0.0.0/16 with 3+ AZs for high availability
- **EKS**: Kubernetes 1.28 with all security features enabled
- **Node Groups**: 3+ m5.large nodes (auto-scales 3-10)
- **NAT Gateways**: One per AZ (3+ NAT Gateways for HA)
- **Add-ons**: All essential add-ons with HA configuration
- **Logging**: All control plane logs enabled, 30-day retention
- **Security**: Private endpoints, restricted public access, VPC Flow Logs
- **Encryption**: KMS encryption for secrets, EBS volumes

## Prerequisites

1. AWS CLI configured with production account access
2. Terraform >= 1.6.0
3. kubectl
4. helm
5. Production AWS account with appropriate IAM permissions
6. S3 bucket and DynamoDB table for Terraform state (configure in `backend.tf`)

## Estimated Monthly Cost

| Resource | Quantity | Unit Cost | Monthly Cost |
|----------|----------|-----------|--------------|
| EKS Control Plane | 1 | $73 | $73 |
| EC2 m5.large | 3-10 | $70 | $210-$700 |
| NAT Gateway | 3 | $35 | $105 |
| NAT Data Transfer | ~500GB | $0.045/GB | $22.50 |
| EBS gp3 (100GB) | 3-10 | $8 | $24-$80 |
| VPC Flow Logs | ~100GB | $0.50/GB | $50 |
| CloudWatch Logs | ~50GB | $0.50/GB | $25 |
| **Total** | | | **~$600-$1,000/month** |

**Cost Optimization:**
- Use Spot instances for non-critical workloads (-70%)
- Use Reserved Instances for predictable workloads (-40%)
- Consider single NAT Gateway for cost savings (less HA)
- Enable ECR endpoints to reduce NAT Gateway data transfer

## Configuration

### 1. Configure Backend

Edit `backend.tf` and uncomment the backend configuration:

```hcl
terraform {
  backend "s3" {
    bucket         = "myapp-terraform-state"
    key            = "prod/terraform.tfstate"
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

**Important:** Update `public_access_cidrs` with your office IPs:

```hcl
public_access_cidrs = ["1.2.3.4/32", "5.6.7.8/32"]  # Replace with actual IPs
```

### 3. Initialize Terraform

```bash
cd terraform/environments/prod
terraform init
```

### 4. Plan

```bash
terraform plan
```

Review the plan carefully. You should see:
- VPC with 3+ AZs
- 3+ NAT Gateways
- EKS cluster with private endpoint
- 3+ node groups
- All add-ons with HA configuration

### 5. Apply

```bash
terraform apply
```

**Warning:** This creates production infrastructure. Review the plan carefully before applying.

This takes ~20-25 minutes.

### 6. Configure kubectl

```bash
aws eks update-kubeconfig --region us-east-1 --name myapp-prod
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
- 3+ nodes in Ready state
- All add-ons running with multiple replicas
- CoreDNS, AWS Load Balancer Controller, Cluster Autoscaler, EBS CSI Driver, Metrics Server

## Production Hardening Checklist

- [x] Multiple AZs (3+)
- [x] Multiple NAT Gateways (one per AZ)
- [x] Private API endpoint enabled
- [x] Public API endpoint restricted to office IPs
- [x] All control plane logs enabled
- [x] 30-day log retention
- [x] VPC Flow Logs enabled
- [x] KMS encryption for secrets
- [x] EBS encryption enabled
- [x] SSM enabled for node access
- [x] Larger instance types (m5.large+)
- [x] Minimum 3 nodes for HA
- [x] All add-ons with HA (multiple replicas)

## Monitoring & Logging

### CloudWatch Logs

All control plane logs are sent to CloudWatch:

```bash
# View API server logs
aws logs tail /aws/eks/myapp-prod/cluster --follow

# View audit logs
aws logs tail /aws/eks/myapp-prod/cluster --log-stream-name audit --follow
```

### VPC Flow Logs

VPC Flow Logs are enabled and sent to CloudWatch:

```bash
# View VPC Flow Logs
aws logs tail /aws/vpc/flowlogs --follow
```

### Metrics

Metrics Server is deployed for HPA/VPA:

```bash
# Check node metrics
kubectl top nodes

# Check pod metrics
kubectl top pods --all-namespaces
```

## Security

### Network Security

- **Private Subnets**: All workloads run in private subnets
- **NAT Gateways**: Outbound internet access only
- **Security Groups**: Least privilege rules
- **VPC Flow Logs**: Enabled for security monitoring

### Access Control

- **Private Endpoint**: Primary access method
- **Public Endpoint**: Restricted to office IPs only
- **IAM**: IRSA for all workloads (no credentials in pods)
- **KMS**: Encryption for all secrets

### Compliance

- All resources tagged appropriately
- Audit logs enabled
- Encryption at rest and in transit
- Least privilege IAM policies

## Troubleshooting

### Cluster Not Accessible

If you can't access the cluster:

1. Check your IP is in `public_access_cidrs`
2. Verify private endpoint is accessible from your VPN
3. Check security groups allow your IP

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
4. Verify OIDC provider is enabled

## Cleanup

**⚠️ WARNING: This will destroy all production infrastructure!**

```bash
terraform destroy
```

**Before destroying:**
- Backup any important data
- Export any needed configurations
- Verify no critical workloads are running
- Coordinate with team

## Support

For issues or questions:
1. Check the main [README.md](../../../README.md)
2. Review [Getting Started Guide](../../../GETTING_STARTED.md)
3. Check module documentation in `../../modules/`

## Next Steps

After deploying:
1. Configure monitoring (Prometheus, Grafana)
2. Set up alerting
3. Configure backup strategy
4. Set up CI/CD pipelines
5. Deploy applications
