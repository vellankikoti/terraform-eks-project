###################
# Splunk Integration via Splunk OpenTelemetry Collector
###################
# This module deploys the Splunk Distribution of OpenTelemetry Collector
# which collects logs, metrics, and traces and forwards them to Splunk.
#
# Architecture:
# - DaemonSet collector: runs on every node, collects container logs and host metrics
# - Gateway collector (optional): aggregation point for traces before forwarding to Splunk
#
# Supports:
# - Splunk Cloud / Splunk Enterprise via HEC (HTTP Event Collector)
# - Splunk Observability Cloud (formerly SignalFx)

resource "helm_release" "splunk_otel_collector" {
  count = var.enabled ? 1 : 0

  name       = "splunk-otel-collector"
  repository = "https://signalfx.github.io/splunk-otel-collector-chart"
  chart      = "splunk-otel-collector"
  version    = var.chart_version
  namespace  = var.namespace

  create_namespace = true

  # Cluster identification
  set {
    name  = "clusterName"
    value = var.cluster_name
  }

  # Splunk Platform (HEC) configuration
  dynamic "set" {
    for_each = var.splunk_hec_token != "" ? [1] : []
    content {
      name  = "splunkPlatform.endpoint"
      value = var.splunk_platform_endpoint
    }
  }

  dynamic "set_sensitive" {
    for_each = var.splunk_hec_token != "" ? [1] : []
    content {
      name  = "splunkPlatform.token"
      value = var.splunk_hec_token
    }
  }

  dynamic "set" {
    for_each = var.splunk_hec_token != "" ? [1] : []
    content {
      name  = "splunkPlatform.index"
      value = var.splunk_index
    }
  }

  dynamic "set" {
    for_each = var.splunk_hec_token != "" ? [1] : []
    content {
      name  = "splunkPlatform.metricsEnabled"
      value = var.enable_metrics
    }
  }

  dynamic "set" {
    for_each = var.splunk_hec_token != "" ? [1] : []
    content {
      name  = "splunkPlatform.logsEnabled"
      value = var.enable_logs
    }
  }

  # Splunk Observability Cloud configuration
  dynamic "set_sensitive" {
    for_each = var.splunk_observability_access_token != "" ? [1] : []
    content {
      name  = "splunkObservability.accessToken"
      value = var.splunk_observability_access_token
    }
  }

  dynamic "set" {
    for_each = var.splunk_observability_access_token != "" ? [1] : []
    content {
      name  = "splunkObservability.realm"
      value = var.splunk_observability_realm
    }
  }

  # Resource configuration
  set {
    name  = "agent.resources.limits.cpu"
    value = var.agent_resources_limits_cpu
  }

  set {
    name  = "agent.resources.limits.memory"
    value = var.agent_resources_limits_memory
  }

  set {
    name  = "agent.resources.requests.cpu"
    value = var.agent_resources_requests_cpu
  }

  set {
    name  = "agent.resources.requests.memory"
    value = var.agent_resources_requests_memory
  }

  # Gateway (optional aggregation point)
  set {
    name  = "gateway.enabled"
    value = var.enable_gateway
  }

  # Environment label
  set {
    name  = "environment"
    value = var.environment
  }
}
