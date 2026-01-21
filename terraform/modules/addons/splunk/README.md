# Splunk Add-on Scaffold

This directory is a **scaffold** for integrating Splunk with your EKS cluster. Splunk integrations can be implemented via:

- Splunk Connect for Kubernetes
- OpenTelemetry Collector with Splunk exporter
- Fluent Bit / Fluentd forwarding to Splunk HEC

Because production Splunk setups are highly specific (URLs, tokens, TLS, index configuration), this module intentionally does **not** impose a specific Helm chart or configuration.

Instead, it provides:

- A non-empty Terraform module
- A place to add your own Splunk integration resources

## How to Use

1. Decide which integration pattern you want (Splunk Connect, OTel, Fluent Bit).
2. Add the relevant Helm release or Kubernetes resources into `main.tf`.
3. Expose configuration via `variables.tf` (HEC URL, token, etc.).
4. Wire it into environments (dev/staging/prod) as needed.

Example (pseudo-code):

```hcl
resource "helm_release" "splunk_connect" {
  name       = "splunk-connect"
  repository = "https://splunk.github.io/splunk-connect-for-kubernetes/"
  chart      = "splunk-connect-for-kubernetes"
  namespace  = "splunk"
  version    = "X.Y.Z"

  set {
    name  = "global.splunk.hec.host"
    value = var.splunk_hec_host
  }

  # ...
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| enabled | Enable Splunk scaffold | `bool` | `false` | no |

## Outputs

| Name | Description |
|------|-------------|
| enabled | Whether Splunk scaffold is enabled |

