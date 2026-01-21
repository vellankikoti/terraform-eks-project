output "namespace" {
  description = "Kubernetes namespace where OpenTelemetry Collector is installed"
  value       = var.namespace
}

output "release_name" {
  description = "Name of the OpenTelemetry Collector Helm release"
  value       = helm_release.this.name
}

