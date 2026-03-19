output "namespace" {
  description = "Kubernetes namespace"
  value       = var.namespace
}

output "release_name" {
  description = "Helm release name"
  value       = helm_release.vpa.name
}
