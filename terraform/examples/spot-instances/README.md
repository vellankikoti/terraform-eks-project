# Spot Instances Example

Demonstrates how to configure mixed on-demand and spot instance node groups for EKS to optimize costs while maintaining reliability.

## Node Group Strategy

| Node Group | Capacity | Instance Types | Purpose |
|------------|----------|---------------|---------|
| system | ON_DEMAND | t3.medium | Critical system workloads (CoreDNS, autoscaler, ingress) |
| general-spot | SPOT | t3.large, t3a.large, m5.large, m5a.large | General application workloads |
| compute-spot | SPOT | c5.xlarge, c5a.xlarge, c6i.xlarge | CPU-intensive workloads (batch, CI/CD, ML) |

## Cost Savings

Spot instances typically cost 60-90% less than on-demand. By keeping only critical system workloads on on-demand and running everything else on spot, you can reduce compute costs significantly.

## Usage

This example outputs the `node_groups` configuration to copy into your environment:

```bash
cd terraform/examples/spot-instances
terraform init
terraform apply

# Copy the node_groups_config output into your environment's terraform.tfvars
```

### Example terraform.tfvars

```hcl
# In terraform/environments/dev/terraform.tfvars

node_groups = {
  system = {
    instance_types = ["t3.medium"]
    capacity_type  = "ON_DEMAND"
    scaling_config = { desired_size = 2, min_size = 2, max_size = 4 }
    labels         = { role = "system" }
    taints         = [{ key = "CriticalAddonsOnly", value = "true", effect = "NO_SCHEDULE" }]
  }
  general-spot = {
    instance_types = ["t3.large", "t3a.large", "m5.large", "m5a.large"]
    capacity_type  = "SPOT"
    scaling_config = { desired_size = 3, min_size = 1, max_size = 10 }
    labels         = { role = "general", capacity-type = "spot" }
    taints         = []
  }
}
```

## Spot Best Practices

1. **Diversify instance types** - Use multiple instance families (t3, t3a, m5, m5a) in each node group. This increases the available capacity pools and reduces interruption frequency.

2. **Use PodDisruptionBudgets** - Protect your applications from sudden spot interruptions:
   ```yaml
   apiVersion: policy/v1
   kind: PodDisruptionBudget
   spec:
     minAvailable: "50%"
     selector:
       matchLabels:
         app: my-app
   ```

3. **Keep system workloads on ON_DEMAND** - CoreDNS, cluster autoscaler, and ingress controllers should always run on on-demand nodes.

4. **Use node selectors for placement** - Target spot nodes explicitly:
   ```yaml
   nodeSelector:
     capacity-type: spot
   ```

5. **Install AWS Node Termination Handler** - Provides graceful shutdown when spot instances receive a 2-minute interruption notice.

6. **Scale from zero for specialized groups** - The compute-spot group starts at 0 and scales up only when pods request those resources.
