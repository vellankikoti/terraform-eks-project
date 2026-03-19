output "enabled" {
  description = "Whether Splunk integration is enabled"
  value       = var.enabled
}

output "namespace" {
  description = "Kubernetes namespace where Splunk collector is deployed"
  value       = var.enabled ? var.namespace : ""
}

output "release_name" {
  description = "Helm release name"
  value       = var.enabled ? helm_release.splunk_otel_collector[0].name : ""
}
