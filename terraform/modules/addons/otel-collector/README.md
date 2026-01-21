# OpenTelemetry Collector Add-on Module

This module deploys the **OpenTelemetry Collector** on EKS using Helm. It collects traces, metrics, and logs and exports them to configured backends.

## Features

- ✅ Helm-based deployment
- ✅ Deployment or DaemonSet mode
- ✅ Custom collector configuration via YAML
- ✅ Configurable resources and replicas

## Usage

```hcl
module "otel_collector" {
  source = "../../modules/addons/otel-collector"

  namespace = "observability"
  mode      = "deployment"

  # Example minimal config
  config_yaml = <<-EOT
    receivers:
      otlp:
        protocols:
          http:
          grpc:
    exporters:
      logging:
        loglevel: info
    service:
      pipelines:
        traces:
          receivers: [otlp]
          exporters: [logging]
  EOT

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| namespace | Namespace for collector | `string` | `"observability"` | no |
| chart_version | Helm chart version | `string` | `"0.93.1"` | no |
| mode | `deployment` or `daemonset` | `string` | `"deployment"` | no |
| replica_count | Replicas (deployment mode) | `number` | `2` | no |
| resources_limits_cpu | CPU limit | `string` | `"500m"` | no |
| resources_limits_memory | Memory limit | `string` | `"512Mi"` | no |
| resources_requests_cpu | CPU request | `string` | `"250m"` | no |
| resources_requests_memory | Memory request | `string` | `"256Mi"` | no |
| config_yaml | Collector config YAML | `string` | `""` | no |
| tags | Additional tags | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| namespace | Collector namespace |
| release_name | Helm release name |

