###################
# Reloader Add-on
# Automatically restarts pods when ConfigMaps/Secrets change
###################

resource "helm_release" "this" {
  name       = "reloader"
  repository = "https://stakater.github.io/stakater-charts"
  chart      = "reloader"
  namespace  = var.namespace
  version    = var.chart_version

  create_namespace = true

  # Watch all namespaces by default
  set {
    name  = "reloader.watchGlobally"
    value = var.watch_globally
  }

  # Resource limits
  set {
    name  = "reloader.deployment.resources.limits.cpu"
    value = var.resources_limits_cpu
  }

  set {
    name  = "reloader.deployment.resources.limits.memory"
    value = var.resources_limits_memory
  }

  set {
    name  = "reloader.deployment.resources.requests.cpu"
    value = var.resources_requests_cpu
  }

  set {
    name  = "reloader.deployment.resources.requests.memory"
    value = var.resources_requests_memory
  }

  tags = var.tags
}

