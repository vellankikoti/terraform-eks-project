output "namespace" {
  description = "Kubernetes namespace where Reloader is installed"
  value       = var.namespace
}

output "release_name" {
  description = "Name of the Reloader Helm release"
  value       = helm_release.this.name
}

