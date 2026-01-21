# Reloader Add-on Module

This module deploys **Reloader** on EKS using Helm. Reloader automatically restarts pods when referenced ConfigMaps or Secrets change.

## Features

- ✅ Watches ConfigMaps and Secrets for changes
- ✅ Restarts Deployments / StatefulSets / DaemonSets automatically
- ✅ Global or namespace-scoped watching
- ✅ Lightweight and production-ready

## Usage

```hcl
module "reloader" {
  source = "../../modules/addons/reloader"

  namespace       = "reloader"
  watch_globally  = true

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| namespace | Namespace for Reloader | `string` | `"reloader"` | no |
| chart_version | Helm chart version | `string` | `"1.0.118"` | no |
| watch_globally | Watch all namespaces | `bool` | `true` | no |
| resources_limits_cpu | CPU limit | `string` | `"200m"` | no |
| resources_limits_memory | Memory limit | `string` | `"256Mi"` | no |
| resources_requests_cpu | CPU request | `string` | `"100m"` | no |
| resources_requests_memory | Memory request | `string` | `"128Mi"` | no |
| tags | Additional tags | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| namespace | Reloader namespace |
| release_name | Helm release name |

