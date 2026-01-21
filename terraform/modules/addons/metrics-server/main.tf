# Metrics Server Add-on
# Collects resource metrics from nodes and pods for Kubernetes autoscaling
# Required for HPA (Horizontal Pod Autoscaler) and VPA (Vertical Pod Autoscaler)

###################
# Helm Release
###################

resource "helm_release" "this" {
  name       = "metrics-server"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  namespace  = var.namespace
  version    = var.chart_version

  create_namespace = true

  # Important: Enable TLS for secure communication
  set {
    name  = "args[0]"
    value = "--kubelet-insecure-tls"
  }

  # For production, you should use proper TLS certificates
  # Remove --kubelet-insecure-tls and configure proper certs
  set {
    name  = "args[1]"
    value = "--kubelet-preferred-address-types=InternalIP"
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

  # High availability (multiple replicas)
  set {
    name  = "replicas"
    value = var.replica_count
  }

  # Pod disruption budget for HA
  set {
    name  = "podDisruptionBudget.enabled"
    value = var.replica_count > 1
  }

  # Priority class for scheduling
  set {
    name  = "priorityClassName"
    value = "system-cluster-critical"
  }

  # Node affinity to run on system nodes
  set {
    name  = "nodeSelector.eks\\.amazonaws\\.com/nodegroup"
    value = var.node_selector_value != null ? var.node_selector_value : ""
  }

  # Tolerations for system workloads
  dynamic "set" {
    for_each = var.tolerations
    content {
      name  = "tolerations[${set.key}].key"
      value = set.value.key
    }
  }

  tags = var.tags
}
