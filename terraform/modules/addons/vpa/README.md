# Vertical Pod Autoscaler (VPA) Module

Automatically recommends and optionally applies optimal CPU/memory requests for pods.

## Modes

| Mode | Behavior | Production Safe? |
|------|----------|:----------------:|
| **Off** (default) | Recommendations only (view via `kubectl describe vpa`) | Yes |
| **Initial** | Sets resources at pod creation only | Yes |
| **Auto** | Updates running pods (causes restarts) | Caution |

## Usage

```hcl
module "vpa" {
  source = "../../modules/addons/vpa"

  # Recommendation-only mode (default, safest)
  updater_enabled = false

  depends_on = [module.eks]
}
```

Then create VPA objects for your workloads:

```yaml
apiVersion: autoscaling.k8s.io/v1
kind: VerticalPodAutoscaler
metadata:
  name: my-app
spec:
  targetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: my-app
  updatePolicy:
    updateMode: "Off"  # Recommend only
```

## Best Practices

- Start with mode "Off" and review recommendations
- VPA and HPA should not both target CPU on the same workload
- Use VPA for memory, HPA for CPU scaling as a pattern
- Requires Metrics Server to be running

## Cost

No additional AWS costs.
