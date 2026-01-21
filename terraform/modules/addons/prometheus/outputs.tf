output "namespace" {
  description = "Kubernetes namespace where Prometheus stack is installed"
  value       = var.namespace
}

output "release_name" {
  description = "Name of the kube-prometheus-stack Helm release"
  value       = helm_release.this.name
}

output "prometheus_ingress_host" {
  description = "Prometheus ingress host (if enabled)"
  value       = var.ingress_enabled ? var.ingress_host : null
}

