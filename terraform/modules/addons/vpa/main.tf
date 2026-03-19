# Vertical Pod Autoscaler (VPA)
# Automatically adjusts CPU and memory requests/limits for pods
#
# Modes:
# - Off (default): Only recommends, doesn't change pods (safest)
# - Initial: Sets requests at pod creation, doesn't update running pods
# - Auto: Updates running pods (can cause restarts)

resource "helm_release" "vpa" {
  name       = "vpa"
  repository = "https://cowboysysop.github.io/charts"
  chart      = "vertical-pod-autoscaler"
  version    = var.chart_version
  namespace  = var.namespace

  create_namespace = true

  # Recommender - analyzes resource usage and provides recommendations
  set {
    name  = "recommender.enabled"
    value = var.recommender_enabled
  }

  set {
    name  = "recommender.resources.requests.cpu"
    value = var.resources_requests_cpu
  }

  set {
    name  = "recommender.resources.requests.memory"
    value = var.resources_requests_memory
  }

  set {
    name  = "recommender.resources.limits.cpu"
    value = var.resources_limits_cpu
  }

  set {
    name  = "recommender.resources.limits.memory"
    value = var.resources_limits_memory
  }

  # Updater - evicts pods that need resource updates
  set {
    name  = "updater.enabled"
    value = var.updater_enabled
  }

  # Admission Controller - sets resources on new pods
  set {
    name  = "admissionController.enabled"
    value = var.enable_admission_controller
  }
}
