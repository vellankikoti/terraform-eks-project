###################
# Prometheus Add-on
# Metrics collection for Kubernetes and applications
###################

resource "helm_release" "this" {
  name       = "kube-prometheus-stack"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  namespace  = var.namespace
  version    = var.chart_version

  create_namespace = true

  # Replica count for Prometheus server
  set {
    name  = "prometheus.prometheusSpec.replicas"
    value = var.prometheus_replica_count
  }

  # Resource limits for Prometheus
  set {
    name  = "prometheus.resources.limits.cpu"
    value = var.prometheus_resources_limits_cpu
  }

  set {
    name  = "prometheus.resources.limits.memory"
    value = var.prometheus_resources_limits_memory
  }

  set {
    name  = "prometheus.resources.requests.cpu"
    value = var.prometheus_resources_requests_cpu
  }

  set {
    name  = "prometheus.resources.requests.memory"
    value = var.prometheus_resources_requests_memory
  }

  # Enable / disable default Grafana
  set {
    name  = "grafana.enabled"
    value = var.enable_builtin_grafana
  }

  # Ingress for Prometheus (optional)
  set {
    name  = "prometheus.ingress.enabled"
    value = var.ingress_enabled
  }

  dynamic "set" {
    for_each = var.ingress_enabled ? [1] : []
    content {
      name  = "prometheus.ingress.ingressClassName"
      value = var.ingress_class_name
    }
  }

  dynamic "set" {
    for_each = var.ingress_enabled ? [1] : []
    content {
      name  = "prometheus.ingress.hosts[0]"
      value = var.ingress_host
    }
  }

  tags = var.tags
}

