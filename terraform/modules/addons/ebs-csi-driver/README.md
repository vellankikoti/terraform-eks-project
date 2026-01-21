# EBS CSI Driver Add-on Module

This module deploys the Amazon EBS Container Storage Interface (CSI) Driver as an EKS-managed add-on. The EBS CSI Driver enables Kubernetes to manage the lifecycle of Amazon EBS volumes for persistent volumes.

## Features

- ✅ EKS-managed add-on (automated updates and lifecycle management)
- ✅ IRSA (IAM Roles for Service Accounts) for secure AWS API access
- ✅ AWS managed IAM policy (least privilege)
- ✅ Production-ready configuration
- ✅ Support for gp2, gp3, io1, io2, sc1, st1 volume types
- ✅ Encryption support via KMS

## What It Does

The EBS CSI Driver allows Kubernetes pods to:
- Create and attach EBS volumes dynamically
- Mount EBS volumes as persistent volumes
- Delete EBS volumes when PVCs are deleted
- Support volume snapshots and restores

## Usage

```hcl
module "ebs_csi_driver" {
  source = "../../modules/addons/ebs-csi-driver"

  cluster_name       = module.eks.cluster_id
  aws_region         = var.aws_region
  oidc_provider_arn  = module.eks.oidc_provider_arn
  oidc_provider_url  = module.eks.oidc_provider_url

  addon_version = "v1.28.0-eksbuild.1"

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
| service_account_name | Service account name | `string` | `"ebs-csi-controller-sa"` | no |
| addon_version | EBS CSI Driver add-on version | `string` | `"v1.28.0-eksbuild.1"` | no |
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

**No additional cost** - The EBS CSI Driver itself is free. You only pay for:
- EBS volumes created by the driver (standard EBS pricing)
- EBS snapshots (if used)
- Data transfer (if volumes are in different AZs)

**Example costs:**
- 100GB gp3 volume: ~$8/month
- 1TB gp3 volume: ~$80/month
- Snapshots: ~$0.05/GB/month

## Example: Creating a PersistentVolumeClaim

After deploying this add-on, you can create PVCs:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: my-pvc
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: gp3
  resources:
    requests:
      storage: 10Gi
```

## Security

- ✅ Uses IRSA (no AWS credentials in pods)
- ✅ AWS managed policy (least privilege)
- ✅ Encrypted volumes supported via StorageClass
- ✅ Network isolation via security groups

## Troubleshooting

**Add-on fails to install:**
- Ensure OIDC provider is enabled on the cluster
- Check IAM role permissions
- Verify add-on version is compatible with Kubernetes version

**PVCs stuck in Pending:**
- Check node group has proper IAM permissions
- Verify security groups allow EBS API access
- Check CloudWatch logs: `/aws/eks/{cluster-name}/cluster`

**Volumes not attaching:**
- Ensure nodes are in same AZ as volume
- Check instance type supports EBS volumes
- Verify EBS CSI Driver pods are running: `kubectl get pods -n kube-system -l app=ebs-csi-controller`

## References

- [AWS EBS CSI Driver Documentation](https://docs.aws.amazon.com/eks/latest/userguide/ebs-csi.html)
- [EKS Add-ons](https://docs.aws.amazon.com/eks/latest/userguide/eks-add-ons.html)
- [Kubernetes Storage Classes](https://kubernetes.io/docs/concepts/storage/storage-classes/)
