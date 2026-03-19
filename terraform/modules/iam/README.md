# IAM Module

Manages EKS access control through IAM roles and the aws-auth ConfigMap.

## Roles Created

| Role | K8s Group | Access Level |
|------|-----------|-------------|
| Admin | system:masters | Full cluster admin |
| Developer | eks-developer | Read-only (pods, services, deployments, logs) |
| CI/CD | eks-cicd | Deploy access (create/update/delete workloads) |

## Usage

```hcl
module "iam" {
  source = "../../modules/iam"

  cluster_name  = module.eks.cluster_id
  cluster_arn   = module.eks.cluster_arn
  node_role_arn = module.eks.node_role_arn

  admin_arns     = ["arn:aws:iam::123456789012:user/admin"]
  developer_arns = ["arn:aws:iam::123456789012:role/developer-team"]
  cicd_arns      = ["arn:aws:iam::123456789012:role/github-actions"]
}
```

## How aws-auth Works

```
IAM Role/User --> aws-auth ConfigMap --> K8s Group --> ClusterRole/Role
```

The aws-auth ConfigMap is the bridge between AWS IAM and Kubernetes RBAC.
When a user authenticates to EKS, AWS maps their IAM identity to a Kubernetes
identity based on this ConfigMap.

## Inputs

| Name | Description | Type | Default |
|------|-------------|------|---------|
| cluster_name | EKS cluster name | string | required |
| cluster_arn | EKS cluster ARN | string | required |
| node_role_arn | Node IAM role ARN | string | required |
| admin_arns | IAM ARNs for admin access | list(string) | [] |
| developer_arns | IAM ARNs for developer access | list(string) | [] |
| cicd_arns | IAM ARNs for CI/CD access | list(string) | [] |

## Outputs

| Name | Description |
|------|-------------|
| admin_role_arn | Admin IAM role ARN |
| developer_role_arn | Developer IAM role ARN |
| cicd_role_arn | CI/CD IAM role ARN |
