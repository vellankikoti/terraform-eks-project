# EFS CSI Driver Add-on Module

This module deploys the Amazon EFS Container Storage Interface (CSI) Driver as an EKS-managed add-on. The EFS CSI Driver enables Kubernetes to manage the lifecycle of Amazon EFS file systems for persistent volumes with shared access across multiple pods.

## Features

- ✅ EKS-managed add-on (automated updates and lifecycle management)
- ✅ IRSA (IAM Roles for Service Accounts) for secure AWS API access
- ✅ AWS managed IAM policy (least privilege)
- ✅ Production-ready configuration
- ✅ Shared storage (multiple pods can mount same volume)
- ✅ Cross-AZ access (unlike EBS)

## What It Does

The EFS CSI Driver allows Kubernetes pods to:
- Create and mount EFS file systems dynamically
- Share storage across multiple pods (ReadWriteMany)
- Access storage from any availability zone
- Support NFS v4.1 protocol

## Usage

```hcl
module "efs_csi_driver" {
  source = "../../modules/addons/efs-csi-driver"

  cluster_name       = module.eks.cluster_id
  aws_region         = var.aws_region
  oidc_provider_arn  = module.eks.oidc_provider_arn
  oidc_provider_url  = module.eks.oidc_provider_url

  addon_version = "v2.0.7-eksbuild.1"

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
| aws | ~> 5.0 |
| eks | EKS cluster with OIDC provider enabled |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| cluster_name | Name of the EKS cluster | `string` | n/a | yes |
| aws_region | AWS region | `string` | n/a | yes |
| oidc_provider_arn | ARN of the OIDC provider | `string` | n/a | yes |
| oidc_provider_url | URL of the OIDC provider (without https://) | `string` | n/a | yes |
| namespace | Kubernetes namespace | `string` | `"kube-system"` | no |
| service_account_name | Service account name | `string` | `"efs-csi-controller-sa"` | no |
| addon_version | EFS CSI Driver add-on version | `string` | `"v2.0.7-eksbuild.1"` | no |
| configuration_values | Additional configuration values | `map(any)` | `null` | no |
| resolve_conflicts_on_update | Conflict resolution on update | `string` | `"OVERWRITE"` | no |
| resolve_conflicts_on_create | Conflict resolution on create | `string` | `"OVERWRITE"` | no |
| tags | Additional tags | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| iam_role_arn | ARN of the IAM role |
| iam_role_name | Name of the IAM role |
| addon_arn | ARN of the EKS add-on |
| addon_version | Version of the add-on |
| service_account_name | Service account name |
| namespace | Kubernetes namespace |

## Cost Implications

**EFS Pricing:**
- Standard storage: ~$0.30/GB/month
- Provisioned throughput: ~$0.05/MiBps/month
- Bursting throughput: Included (up to 100 MiBps per TB)
- Data transfer: Standard AWS data transfer pricing

**Example costs:**
- 100GB EFS: ~$30/month
- 1TB EFS: ~$300/month
- Plus data transfer costs

**Note:** EFS is more expensive than EBS but provides shared access and cross-AZ capabilities.

## Example: Creating a PersistentVolumeClaim

After deploying this add-on, you can create PVCs with ReadWriteMany access:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: my-efs-pvc
spec:
  accessModes:
    - ReadWriteMany  # EFS supports shared access
  storageClassName: efs-sc
  resources:
    requests:
      storage: 10Gi
```

**StorageClass example:**

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: efs-sc
provisioner: efs.csi.aws.com
parameters:
  provisioningMode: efs-ap  # Access Point mode
  fileSystemId: fs-xxxxx     # Your EFS file system ID
  directoryPerms: "755"
```

## When to Use EFS vs EBS

**Use EFS when:**
- Multiple pods need to share the same storage
- Need ReadWriteMany access mode
- Need cross-AZ access
- Running stateful applications that need shared storage (e.g., shared configs, logs)

**Use EBS when:**
- Single pod needs storage (ReadWriteOnce)
- Lower cost is important
- Higher IOPS needed
- Database workloads (better performance)

## Security

- ✅ Uses IRSA (no AWS credentials in pods)
- ✅ AWS managed policy (least privilege)
- ✅ Network isolation via security groups
- ✅ Encryption at rest supported
- ✅ Encryption in transit supported

## Troubleshooting

**Add-on fails to install:**
- Ensure OIDC provider is enabled on the cluster
- Check IAM role permissions
- Verify add-on version is compatible with Kubernetes version

**PVCs stuck in Pending:**
- Ensure EFS file system exists and is accessible
- Verify security groups allow NFS traffic (port 2049)
- Check EFS mount targets are in correct subnets
- Verify EFS CSI Driver pods are running: `kubectl get pods -n kube-system -l app=efs-csi-controller`

**Mount failures:**
- Check EFS security groups allow traffic from node security groups
- Verify EFS file system is in same VPC as cluster
- Check CloudWatch logs: `/aws/eks/{cluster-name}/cluster`

## References

- [AWS EFS CSI Driver Documentation](https://docs.aws.amazon.com/eks/latest/userguide/efs-csi.html)
- [EKS Add-ons](https://docs.aws.amazon.com/eks/latest/userguide/eks-add-ons.html)
- [EFS Pricing](https://aws.amazon.com/efs/pricing/)
