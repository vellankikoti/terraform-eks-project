###################
# OpenTelemetry Collector Add-on
# Collects traces, metrics, and logs and exports to backends (e.g., OTLP, Prometheus, Jaeger)
###################

resource "helm_release" "this" {
  name       = "otel-collector"
  repository = "https://open-telemetry.github.io/opentelemetry-helm-charts"
  chart      = "opentelemetry-collector"
  namespace  = var.namespace
  version    = var.chart_version

  create_namespace = true

  # Mode: deployment / daemonset
  set {
    name  = "mode"
    value = var.mode
  }

  # Resource limits
  set {
    name  = "resources.limits.cpu"
    value = var.resources_limits_cpu
  }

  set {
    name  = "resources.limits.memory"
    value = var.resources_limits_memory
  }

  set {
    name  = "resources.requests.cpu"
    value = var.resources_requests_cpu
  }

  set {
    name  = "resources.requests.memory"
    value = var.resources_requests_memory
  }

  # Replica count for deployment mode
  set {
    name  = "replicaCount"
    value = var.replica_count
  }

  # Custom configuration (YAML)
  dynamic "set" {
    for_each = var.config_yaml != "" ? [1] : []
    content {
      name  = "config"
      value = var.config_yaml
    }
  }

  tags = var.tags
}

