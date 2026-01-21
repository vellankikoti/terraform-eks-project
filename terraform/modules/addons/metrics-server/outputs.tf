output "namespace" {
  description = "Kubernetes namespace where Metrics Server is installed"
  value       = var.namespace
}

output "release_name" {
  description = "Name of the Helm release"
  value       = helm_release.this.name
}

output "release_version" {
  description = "Version of the Helm release"
  value       = helm_release.this.version
}
