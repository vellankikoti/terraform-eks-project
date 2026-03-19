# Multi-Team RBAC Example

Demonstrates how to configure Kubernetes RBAC, network policies, and resource quotas for a multi-team EKS cluster. Each team gets an isolated namespace with controlled access and resource limits.

## What It Creates (Per Team)

| Resource | Purpose |
|----------|---------|
| Namespace | Isolated environment for the team |
| Role | Full access to workload resources within the namespace |
| RoleBinding | Binds the role to a Kubernetes group |
| NetworkPolicy | Restricts ingress to same-namespace and kube-system only |
| ResourceQuota | Limits total compute and object counts |
| LimitRange | Sets default and max resource requests per container |

Additionally creates a **cluster-wide read-only ClusterRole** for platform engineers and on-call staff.

## Default Teams

| Team | CPU Quota | Memory Quota | Max Pods |
|------|-----------|-------------|----------|
| frontend | 4 req / 8 limit | 8Gi req / 16Gi limit | 20 |
| backend | 8 req / 16 limit | 16Gi req / 32Gi limit | 40 |
| data | 16 req / 32 limit | 32Gi req / 64Gi limit | 30 |

## Deploy

```bash
cd terraform/examples/multi-team-rbac

terraform init

terraform apply -var="cluster_name=myapp-dev"
```

## Customize Teams

Override the `teams` variable in a `terraform.tfvars` file:

```hcl
cluster_name = "myapp-dev"

teams = {
  platform = {
    lead        = "dave@example.com"
    description = "Platform engineering"
    quota = {
      cpu_request        = "8"
      memory_request     = "16Gi"
      cpu_limit          = "16"
      memory_limit       = "32Gi"
      max_pods           = "30"
      max_services       = "15"
      max_load_balancers = "3"
      max_pvcs           = "10"
      max_secrets        = "25"
      max_configmaps     = "25"
    }
  }
}
```

## Map IAM Roles to Kubernetes Groups

For teams to authenticate, map their IAM roles to the Kubernetes groups in the `aws-auth` ConfigMap:

```yaml
# aws-auth ConfigMap mapRoles entry
- rolearn: arn:aws:iam::123456789012:role/FrontendTeamRole
  username: "{{SessionName}}"
  groups:
    - team-frontend           # Matches the RoleBinding group
    - cluster-readonly        # Also gets read-only cluster access

- rolearn: arn:aws:iam::123456789012:role/BackendTeamRole
  username: "{{SessionName}}"
  groups:
    - team-backend
    - cluster-readonly
```

## Verify

```bash
# Check namespaces
kubectl get namespaces -l managed-by=terraform

# Check quotas
kubectl describe resourcequota -n frontend

# Check network policies
kubectl get networkpolicies -n backend

# Check limit ranges
kubectl describe limitrange -n data

# Test as a specific team (requires kubeconfig with team IAM role)
kubectl auth can-i create deployments -n frontend --as-group=team-frontend
```

## Clean Up

```bash
terraform destroy -var="cluster_name=myapp-dev"
```
