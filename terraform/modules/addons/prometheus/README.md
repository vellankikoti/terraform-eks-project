# Prometheus Add-on Module (kube-prometheus-stack)

This module deploys the **kube-prometheus-stack** Helm chart on EKS. It includes Prometheus, Alertmanager, and Kubernetes metrics exporters.

## Features

- ✅ Full Prometheus stack (Prometheus, Alertmanager, exporters)
- ✅ Configurable Prometheus resources and replica count
- ✅ Optional built-in Grafana
- ✅ Optional ALB ingress

## Usage

```hcl
module "prometheus" {
  source = "../../modules/addons/prometheus"

  namespace = "monitoring"

  prometheus_replica_count = 1

  ingress_enabled    = true
  ingress_class_name = "alb"
  ingress_host       = "prometheus.example.com"

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| namespace | Namespace for monitoring stack | `string` | `"monitoring"` | no |
| chart_version | Helm chart version | `string` | `"65.5.1"` | no |
| prometheus_replica_count | Prometheus replicas | `number` | `1` | no |
| prometheus_resources_limits_cpu | CPU limit | `string` | `"1000m"` | no |
| prometheus_resources_limits_memory | Memory limit | `string` | `"2Gi"` | no |
| prometheus_resources_requests_cpu | CPU request | `string` | `"500m"` | no |
| prometheus_resources_requests_memory | Memory request | `string` | `"1Gi"` | no |
| enable_builtin_grafana | Enable built-in Grafana | `bool` | `false` | no |
| ingress_enabled | Enable ingress | `bool` | `false` | no |
| ingress_class_name | Ingress class | `string` | `"alb"` | no |
| ingress_host | Ingress host | `string` | `"prometheus.example.com"` | no |
| tags | Additional tags | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| namespace | Monitoring namespace |
| release_name | Helm release name |
| prometheus_ingress_host | Prometheus ingress host (if enabled) |

## Cost

Prometheus is memory/CPU intensive. Costs come from:

- EC2 nodes running Prometheus and exporters
- EBS volumes if using persistent storage
- CloudWatch or S3 if you export metrics

## Verification

```bash
kubectl get pods -n monitoring
kubectl get svc -n monitoring
```

If ingress is enabled, access:

- `https://prometheus.example.com` (or your configured host)

