###################
# Splunk Add-on (Placeholder)
# This module is a scaffold for integrating Splunk (e.g., via OpenTelemetry or Fluent Bit).
###################

# NOTE:
# Splunk integration patterns vary widely (HTTP Event Collector, Splunk Connect for Kubernetes,
# OpenTelemetry Collector, etc.). This module intentionally provides a minimal scaffold and
# documentation, rather than enforcing a specific vendor chart.

locals {
  # Placeholder local to avoid empty file
  splunk_integration_enabled = var.enabled
}

