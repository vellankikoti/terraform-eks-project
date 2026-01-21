# Metrics Server Add-on Module

This module deploys the Kubernetes Metrics Server using Helm. Metrics Server collects resource usage metrics (CPU and memory) from nodes and pods, enabling Kubernetes autoscaling features like HPA (Horizontal Pod Autoscaler) and VPA (Vertical Pod Autoscaler).

## Features

- ✅ Helm-based deployment (easy updates)
- ✅ High availability (multiple replicas)
- ✅ Production-ready resource limits
- ✅ System priority class
- ✅ Pod disruption budget for HA
- ✅ Required for HPA/VPA to work

## What It Does

Metrics Server:
- Collects CPU and memory usage from kubelets
- Aggregates metrics for the Kubernetes API
- Enables `kubectl top nodes` and `kubectl top pods`
- Required for HPA (Horizontal Pod Autoscaler)
- Required for VPA (Vertical Pod Autoscaler)

## Usage

```hcl
module "metrics_server" {
  source = "../../modules/addons/metrics-server"

  cluster_name = module.eks.cluster_id

  replica_count = 2

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
| kubernetes | EKS cluster running |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| cluster_name | Name of the EKS cluster | `string` | n/a | yes |
| namespace | Kubernetes namespace | `string` | `"kube-system"` | no |
| chart_version | Helm chart version | `string` | `"3.11.0"` | no |
| replica_count | Number of replicas | `number` | `2` | no |
| resources_limits_cpu | CPU limit | `string` | `"100m"` | no |
| resources_limits_memory | Memory limit | `string` | `"200Mi"` | no |
| resources_requests_cpu | CPU request | `string` | `"100m"` | no |
| resources_requests_memory | Memory request | `string` | `"200Mi"` | no |
| node_selector_value | Node selector value | `string` | `null` | no |
| tolerations | Pod tolerations | `list(object)` | `[]` | no |
| tags | Additional tags | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| namespace | Kubernetes namespace |
| release_name | Helm release name |
| release_version | Helm release version |

## Cost Implications

**No additional cost** - Metrics Server runs on existing nodes and consumes minimal resources (~100m CPU, 200Mi memory per replica).

## Verification

After deployment, verify Metrics Server is working:

```bash
# Check if Metrics Server pods are running
kubectl get pods -n kube-system -l k8s-app=metrics-server

# Check node metrics
kubectl top nodes

# Check pod metrics
kubectl top pods --all-namespaces
```

## Example: Using with HPA

Once Metrics Server is deployed, you can create an HPA:

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: my-app-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: my-app
  minReplicas: 2
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 80
```

## Security

- ✅ Runs in kube-system namespace
- ✅ System priority class (scheduled first)
- ✅ Minimal resource footprint
- ⚠️ Uses `--kubelet-insecure-tls` for simplicity (configure proper TLS for production)

## Troubleshooting

**Metrics not available:**
- Check Metrics Server pods: `kubectl get pods -n kube-system -l k8s-app=metrics-server`
- Check logs: `kubectl logs -n kube-system -l k8s-app=metrics-server`
- Verify kubelet is accessible from Metrics Server pods

**HPA not working:**
- Ensure Metrics Server is running
- Check HPA status: `kubectl describe hpa <name>`
- Verify metrics API: `kubectl get --raw /apis/metrics.k8s.io/v1beta1/nodes`

**High resource usage:**
- Reduce replica count (1 for dev, 2+ for prod)
- Adjust resource limits if needed

## References

- [Metrics Server GitHub](https://github.com/kubernetes-sigs/metrics-server)
- [Kubernetes HPA](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/)
- [Metrics Server Helm Chart](https://github.com/kubernetes-sigs/metrics-server/tree/master/charts/metrics-server)
