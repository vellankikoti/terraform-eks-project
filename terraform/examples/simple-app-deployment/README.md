# Simple App Deployment Example

Deploys a complete Nginx application on EKS with production best practices including rolling updates, health checks, autoscaling, and ALB ingress.

## What It Creates

| Resource | Purpose |
|----------|---------|
| Namespace | Isolated environment for the application |
| ConfigMap | Custom Nginx configuration with health endpoints |
| Deployment | 3 replicas with rolling updates, resource limits, and health probes |
| Service (ClusterIP) | Internal load balancing across pods |
| Ingress (ALB) | External access via AWS Application Load Balancer |
| HPA | Autoscales pods at 70% CPU utilization |

## Prerequisites

- EKS cluster deployed (via `terraform/environments/dev`)
- AWS Load Balancer Controller add-on installed
- Metrics Server installed (for HPA)
- `kubectl` and `aws` CLI configured

## Deploy

```bash
cd terraform/examples/simple-app-deployment

terraform init

# Deploy to your cluster
terraform apply \
  -var="cluster_name=myapp-dev" \
  -var="aws_region=us-east-1"
```

## Customize

Override defaults with a `terraform.tfvars` file:

```hcl
cluster_name   = "myapp-dev"
aws_region     = "us-east-1"
app_name       = "my-web-app"
namespace      = "web-apps"
replicas       = 3
image          = "nginx:1.25-alpine"
cpu_request    = "250m"
memory_request = "256Mi"
domain_name    = "myapp.example.com"
```

## Verify Deployment

```bash
# Check pods are running
kubectl get pods -n demo-app

# Check service
kubectl get svc -n demo-app

# Check ingress and get ALB URL
kubectl get ingress -n demo-app

# Test health endpoint
kubectl port-forward svc/nginx-demo 8080:80 -n demo-app
curl http://localhost:8080/healthz
```

## Enable HTTPS

To enable HTTPS, uncomment the SSL annotations in `main.tf` and provide your ACM certificate ARN:

```hcl
"alb.ingress.kubernetes.io/listen-ports"    = "[{\"HTTPS\": 443}]"
"alb.ingress.kubernetes.io/certificate-arn" = "arn:aws:acm:us-east-1:123456789012:certificate/your-cert-id"
"alb.ingress.kubernetes.io/ssl-redirect"    = "443"
```

## Clean Up

```bash
terraform destroy \
  -var="cluster_name=myapp-dev" \
  -var="aws_region=us-east-1"
```
