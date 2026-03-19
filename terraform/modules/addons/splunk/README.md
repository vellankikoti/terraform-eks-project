# Splunk Integration Module

Deploys the Splunk Distribution of OpenTelemetry Collector for log, metric, and trace forwarding to Splunk.

## Supported Backends

- **Splunk Platform** (Cloud/Enterprise) via HTTP Event Collector (HEC)
- **Splunk Observability Cloud** (formerly SignalFx)

## Architecture

```
+--------+     +--------+     +--------+
| Node 1 |     | Node 2 |     | Node 3 |
| Agent  |     | Agent  |     | Agent  |  <-- DaemonSet collects logs/metrics
+---+----+     +---+----+     +---+----+
    |              |              |
    v              v              v
  +-------------------------------+
  |     Gateway (optional)        |  <-- Aggregation for traces
  +-------------------------------+
              |
              v
    +-------------------+
    | Splunk Platform   |
    | or Observability  |
    +-------------------+
```

## Usage

### Splunk Platform (HEC)

```hcl
module "splunk" {
  source = "../../modules/addons/splunk"

  enabled      = true
  cluster_name = "my-cluster"
  environment  = "prod"

  splunk_platform_endpoint = "https://splunk.example.com:8088/services/collector"
  splunk_hec_token         = var.splunk_hec_token  # Use secrets!
  splunk_index             = "kubernetes"
}
```

### Splunk Observability Cloud

```hcl
module "splunk" {
  source = "../../modules/addons/splunk"

  enabled      = true
  cluster_name = "my-cluster"
  environment  = "prod"

  splunk_observability_access_token = var.splunk_access_token
  splunk_observability_realm        = "us0"
}
```

## Inputs

| Name | Description | Type | Default |
|------|-------------|------|---------|
| enabled | Enable Splunk integration | bool | false |
| cluster_name | EKS cluster name | string | "" |
| environment | Environment name | string | "" |
| splunk_platform_endpoint | Splunk HEC endpoint URL | string | "" |
| splunk_hec_token | Splunk HEC token (sensitive) | string | "" |
| splunk_index | Splunk index for logs | string | "main" |
| splunk_observability_access_token | Splunk Observability Cloud token | string | "" |
| splunk_observability_realm | Splunk Observability Cloud realm | string | "us0" |
| enable_gateway | Enable gateway for trace aggregation | bool | false |

## Outputs

| Name | Description |
|------|-------------|
| enabled | Whether Splunk integration is enabled |
| namespace | Kubernetes namespace |
| release_name | Helm release name |

## Cost

- No additional AWS costs (runs as DaemonSet pods)
- Splunk licensing costs apply based on data volume ingested
