# Simple App Deployment Example
# Deploys an Nginx application on EKS with best practices:
# - Deployment with rolling updates, health checks, and resource limits
# - Service, Ingress (ALB), HPA, and ConfigMap
#
# Usage:
#   cd terraform/examples/simple-app-deployment
#   terraform init
#   terraform apply -var="cluster_name=myapp-dev" -var="aws_region=us-east-1"

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Fetch EKS cluster details to configure the Kubernetes provider
data "aws_eks_cluster" "this" {
  name = var.cluster_name
}

data "aws_eks_cluster_auth" "this" {
  name = var.cluster_name
}

# Configure Kubernetes provider using EKS cluster auth
provider "kubernetes" {
  host                   = data.aws_eks_cluster.this.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    args        = ["eks", "get-token", "--cluster-name", var.cluster_name]
    command     = "aws"
  }
}

###########################
# Namespace
# Isolate the application in its own namespace for security and resource management
###########################

resource "kubernetes_namespace" "app" {
  metadata {
    name = var.namespace

    labels = {
      app         = var.app_name
      managed-by  = "terraform"
      environment = "example"
    }
  }
}

###########################
# ConfigMap - Nginx Configuration
# Custom nginx config with health check endpoint and sensible defaults
###########################

resource "kubernetes_config_map" "nginx_config" {
  metadata {
    name      = "${var.app_name}-config"
    namespace = kubernetes_namespace.app.metadata[0].name
  }

  data = {
    "default.conf" = <<-EOT
      server {
        listen 80;
        server_name _;

        # Health check endpoint for Kubernetes probes
        location /healthz {
          access_log off;
          return 200 "OK\n";
          add_header Content-Type text/plain;
        }

        # Readiness check - same as health for this simple app
        location /ready {
          access_log off;
          return 200 "READY\n";
          add_header Content-Type text/plain;
        }

        # Main application
        location / {
          root   /usr/share/nginx/html;
          index  index.html index.htm;
        }

        # Custom error pages
        error_page 500 502 503 504 /50x.html;
        location = /50x.html {
          root /usr/share/nginx/html;
        }
      }
    EOT
  }
}

###########################
# Deployment
# Core workload with rolling updates, health checks, and resource management
###########################

resource "kubernetes_deployment" "app" {
  metadata {
    name      = var.app_name
    namespace = kubernetes_namespace.app.metadata[0].name

    labels = {
      app = var.app_name
    }
  }

  spec {
    replicas = var.replicas

    # Rolling update strategy: deploy new pods gradually to ensure zero-downtime
    strategy {
      type = "RollingUpdate"
      rolling_update {
        max_surge       = "25%"   # Allow 25% more pods during update
        max_unavailable = "25%"   # Allow 25% of pods to be unavailable during update
      }
    }

    selector {
      match_labels = {
        app = var.app_name
      }
    }

    template {
      metadata {
        labels = {
          app = var.app_name
        }
      }

      spec {
        # Spread pods across nodes for high availability
        topology_spread_constraint {
          max_skew            = 1
          topology_key        = "kubernetes.io/hostname"
          when_unsatisfiable  = "ScheduleAnyway"
          label_selector {
            match_labels = {
              app = var.app_name
            }
          }
        }

        container {
          name  = var.app_name
          image = var.image

          port {
            container_port = 80
            protocol       = "TCP"
          }

          # Resource requests and limits
          # Requests: guaranteed resources for scheduling
          # Limits: maximum resources the container can use
          resources {
            requests = {
              cpu    = var.cpu_request
              memory = var.memory_request
            }
            limits = {
              cpu    = var.cpu_request     # Set equal to request to get Guaranteed QoS
              memory = var.memory_request  # Set equal to request to get Guaranteed QoS
            }
          }

          # Liveness probe: restart the container if it fails
          # Checks /healthz every 10 seconds, allows 3 failures before restart
          liveness_probe {
            http_get {
              path = "/healthz"
              port = 80
            }
            initial_delay_seconds = 10
            period_seconds        = 10
            timeout_seconds       = 3
            failure_threshold     = 3
            success_threshold     = 1
          }

          # Readiness probe: remove from service if not ready
          # Checks /ready every 5 seconds, allows 3 failures before removing from service
          readiness_probe {
            http_get {
              path = "/ready"
              port = 80
            }
            initial_delay_seconds = 5
            period_seconds        = 5
            timeout_seconds       = 3
            failure_threshold     = 3
            success_threshold     = 1
          }

          # Mount custom nginx configuration
          volume_mount {
            name       = "nginx-config"
            mount_path = "/etc/nginx/conf.d"
            read_only  = true
          }
        }

        # Volume from ConfigMap
        volume {
          name = "nginx-config"
          config_map {
            name = kubernetes_config_map.nginx_config.metadata[0].name
          }
        }
      }
    }
  }

  # Wait for the deployment to be available before marking as complete
  wait_for_rollout = true
}

###########################
# Service (ClusterIP)
# Internal service for routing traffic to the deployment pods
###########################

resource "kubernetes_service" "app" {
  metadata {
    name      = var.app_name
    namespace = kubernetes_namespace.app.metadata[0].name

    labels = {
      app = var.app_name
    }
  }

  spec {
    type = "ClusterIP"

    selector = {
      app = var.app_name
    }

    port {
      name        = "http"
      port        = 80
      target_port = 80
      protocol    = "TCP"
    }
  }
}

###########################
# Ingress (ALB Ingress Controller)
# Exposes the service externally via AWS Application Load Balancer
# Requires the AWS Load Balancer Controller add-on to be installed
###########################

resource "kubernetes_ingress_v1" "app" {
  metadata {
    name      = var.app_name
    namespace = kubernetes_namespace.app.metadata[0].name

    annotations = {
      # ALB Ingress Controller annotations
      "kubernetes.io/ingress.class"               = "alb"
      "alb.ingress.kubernetes.io/scheme"          = "internet-facing"   # Use "internal" for private apps
      "alb.ingress.kubernetes.io/target-type"     = "ip"                # Required for Fargate or recommended for VPC CNI
      "alb.ingress.kubernetes.io/listen-ports"    = "[{\"HTTP\": 80}]"
      "alb.ingress.kubernetes.io/healthcheck-path" = "/healthz"
      "alb.ingress.kubernetes.io/group.name"      = "shared-alb"       # Share ALB across multiple ingresses to save cost

      # Optional: Enable HTTPS (uncomment and configure certificate ARN)
      # "alb.ingress.kubernetes.io/listen-ports"      = "[{\"HTTPS\": 443}]"
      # "alb.ingress.kubernetes.io/certificate-arn"   = "arn:aws:acm:us-east-1:123456789012:certificate/xxx"
      # "alb.ingress.kubernetes.io/ssl-redirect"      = "443"
    }
  }

  spec {
    rule {
      host = var.domain_name

      http {
        path {
          path      = "/"
          path_type = "Prefix"

          backend {
            service {
              name = kubernetes_service.app.metadata[0].name
              port {
                number = 80
              }
            }
          }
        }
      }
    }
  }
}

###########################
# Horizontal Pod Autoscaler (HPA)
# Automatically scales pods based on CPU utilization
# Requires Metrics Server to be installed (included in the EKS add-ons)
###########################

resource "kubernetes_horizontal_pod_autoscaler_v2" "app" {
  metadata {
    name      = var.app_name
    namespace = kubernetes_namespace.app.metadata[0].name
  }

  spec {
    # Reference the deployment to scale
    scale_target_ref {
      api_version = "apps/v1"
      kind        = "Deployment"
      name        = kubernetes_deployment.app.metadata[0].name
    }

    # Min and max replica bounds
    min_replicas = var.replicas
    max_replicas = var.replicas * 3  # Scale up to 3x the base replica count

    # Scale when average CPU exceeds 70%
    metric {
      type = "Resource"
      resource {
        name = "cpu"
        target {
          type                = "Utilization"
          average_utilization = 70
        }
      }
    }

    # Scaling behavior: scale up quickly, scale down slowly
    behavior {
      scale_up {
        stabilization_window_seconds = 60
        policy {
          type           = "Percent"
          value          = 100
          period_seconds = 60
        }
      }
      scale_down {
        stabilization_window_seconds = 300  # Wait 5 minutes before scaling down
        policy {
          type           = "Percent"
          value          = 25
          period_seconds = 60
        }
      }
    }
  }
}
