###################
# Grafana Add-on
# Dashboards and visualization for Prometheus metrics
###################

resource "helm_release" "this" {
  name       = "grafana"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "grafana"
  namespace  = var.namespace
  version    = var.chart_version

  create_namespace = true

  # Admin credentials (use Kubernetes secret values)
  set {
    name  = "adminUser"
    value = var.admin_user
  }

  set {
    name  = "adminPassword"
    value = var.admin_password
  }

  # Replica count for HA (primarily for prod/staging)
  set {
    name  = "replicas"
    value = var.replica_count
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

  # Ingress (optional)
  set {
    name  = "ingress.enabled"
    value = var.ingress_enabled
  }

  dynamic "set" {
    for_each = var.ingress_enabled ? [1] : []
    content {
      name  = "ingress.ingressClassName"
      value = var.ingress_class_name
    }
  }

  dynamic "set" {
    for_each = var.ingress_enabled ? [1] : []
    content {
      name  = "ingress.hosts[0]"
      value = var.ingress_host
    }
  }

  # Connect to Prometheus (optional, via datasource)
  dynamic "set" {
    for_each = var.prometheus_url != "" ? [1] : []
    content {
      name  = "datasources.datasources\\.yaml.apiVersion"
      value = "1"
    }
  }

  dynamic "set" {
    for_each = var.prometheus_url != "" ? [1] : []
    content {
      name  = "datasources.datasources\\.yaml.datasources[0].name"
      value = "Prometheus"
    }
  }

  dynamic "set" {
    for_each = var.prometheus_url != "" ? [1] : []
    content {
      name  = "datasources.datasources\\.yaml.datasources[0].type"
      value = "prometheus"
    }
  }

  dynamic "set" {
    for_each = var.prometheus_url != "" ? [1] : []
    content {
      name  = "datasources.datasources\\.yaml.datasources[0].url"
      value = var.prometheus_url
    }
  }

  tags = var.tags
}

