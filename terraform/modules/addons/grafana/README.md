# Grafana Add-on Module

This module deploys **Grafana** on EKS using Helm. Grafana provides dashboards and visualization for Prometheus and other data sources.

## Features

- ✅ Helm-based deployment
- ✅ Configurable replica count and resources
- ✅ Optional ALB ingress
- ✅ Optional Prometheus datasource configuration

## Usage

```hcl
module "grafana" {
  source = "../../modules/addons/grafana"

  namespace  = "grafana"
  prometheus_url = "http://kube-prometheus-stack-prometheus.monitoring.svc:9090"

  ingress_enabled    = true
  ingress_class_name = "alb"
  ingress_host       = "grafana.example.com"

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| namespace | Namespace for Grafana | `string` | `"grafana"` | no |
| chart_version | Helm chart version | `string` | `"7.3.9"` | no |
| admin_user | Grafana admin user | `string` | `"admin"` | no |
| admin_password | Grafana admin password | `string` | `"admin"` | no |
| replica_count | Number of replicas | `number` | `1` | no |
| resources_limits_cpu | CPU limit | `string` | `"500m"` | no |
| resources_limits_memory | Memory limit | `string` | `"512Mi"` | no |
| resources_requests_cpu | CPU request | `string` | `"250m"` | no |
| resources_requests_memory | Memory request | `string` | `"256Mi"` | no |
| ingress_enabled | Enable ingress | `bool` | `false` | no |
| ingress_class_name | Ingress class | `string` | `"alb"` | no |
| ingress_host | Ingress host | `string` | `"grafana.example.com"` | no |
| prometheus_url | Prometheus URL for datasource | `string` | `""` | no |
| tags | Additional tags | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| namespace | Grafana namespace |
| release_name | Helm release name |
| ingress_host | Grafana ingress host (if enabled) |

## Cost

Grafana itself has **no direct AWS cost**. You pay for:

- EC2 nodes running Grafana
- Network traffic for dashboards

## Verification

```bash
kubectl get pods -n grafana
kubectl get svc -n grafana
```

If ingress is enabled, access:

- `https://grafana.example.com` (or your configured host)

