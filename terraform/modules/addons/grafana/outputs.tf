output "namespace" {
  description = "Kubernetes namespace where Grafana is installed"
  value       = var.namespace
}

output "release_name" {
  description = "Name of the Grafana Helm release"
  value       = helm_release.this.name
}

output "ingress_host" {
  description = "Grafana ingress host (if enabled)"
  value       = var.ingress_enabled ? var.ingress_host : null
}

