# 05 - Terraform + Helm + Kubernetes: Three Worlds Colliding

> **Goal**: Master the intersection of Terraform, Helm, and Kubernetes -- where most production incidents happen. Understand dependency ordering, values management, GitOps integration, and how to debug when things go wrong.

---

## Table of Contents

1. [The Three Worlds](#1-the-three-worlds)
2. [How Terraform Talks to Kubernetes](#2-how-terraform-talks-to-kubernetes)
3. [Helm Deep Dive for Terraform Engineers](#3-helm-deep-dive-for-terraform-engineers)
4. [The Terraform Helm Provider](#4-the-terraform-helm-provider)
5. [Dependency Ordering: The Hard Part](#5-dependency-ordering-the-hard-part)
6. [Values Management Patterns](#6-values-management-patterns)
7. [GitOps Integration](#7-gitops-integration)
8. [Debugging Helm in Terraform](#8-debugging-helm-in-terraform)
9. [Production Patterns and Recipes](#9-production-patterns-and-recipes)
10. [Anti-Patterns](#10-anti-patterns)
11. [Test Yourself](#11-test-yourself)

---

## 1. The Three Worlds

When you deploy applications on EKS, you are operating across three distinct systems, each with its own state, its own lifecycle, and its own failure modes.

```
┌─────────────────────────────────────────────────────────────────┐
│                    THE THREE WORLDS                               │
│                                                                   │
│  ┌──────────────────┐                                            │
│  │   TERRAFORM       │  "I create and manage cloud resources"     │
│  │                   │  State: S3 bucket                          │
│  │  AWS resources    │  Lifecycle: terraform apply                │
│  │  IAM roles        │  Failure mode: state drift, API errors     │
│  │  VPC, subnets     │                                            │
│  │  EKS cluster      │                                            │
│  └────────┬──────────┘                                            │
│           │ creates cluster, then...                              │
│           v                                                       │
│  ┌──────────────────┐                                            │
│  │   KUBERNETES      │  "I orchestrate containers"                │
│  │                   │  State: etcd (inside EKS control plane)    │
│  │  Deployments      │  Lifecycle: kubectl apply / Helm           │
│  │  Services         │  Failure mode: pod crashes, OOM, network   │
│  │  ConfigMaps       │                                            │
│  │  Namespaces       │                                            │
│  └────────┬──────────┘                                            │
│           │ needs charts to deploy apps, so...                    │
│           v                                                       │
│  ┌──────────────────┐                                            │
│  │   HELM            │  "I package and deploy K8s applications"   │
│  │                   │  State: Secrets in K8s (Helm releases)     │
│  │  Charts           │  Lifecycle: helm install / upgrade         │
│  │  Values           │  Failure mode: template errors, rollbacks  │
│  │  Releases         │                                            │
│  └──────────────────┘                                            │
└─────────────────────────────────────────────────────────────────┘
```

### Why This Matters

The pain comes from the boundaries between these worlds. Each has its own:

- **State mechanism**: Terraform uses S3, Kubernetes uses etcd, Helm uses Kubernetes Secrets
- **Reconciliation model**: Terraform is imperative-declarative (you run `apply`), Kubernetes controllers are continuously reconciling, Helm is imperative (you run `upgrade`)
- **Error handling**: Terraform rolls back nothing (it stops and leaves partial state), Kubernetes self-heals, Helm can rollback releases

When you use Terraform to deploy Helm charts (which deploy Kubernetes resources), you are asking one state system to manage another state system that manages a third state system. This is powerful but fragile. Understanding the boundaries is essential.

---

## 2. How Terraform Talks to Kubernetes

### The Authentication Problem

Before Terraform can deploy anything to Kubernetes, it needs to authenticate. This creates a chicken-and-egg situation: Terraform creates the EKS cluster, but it also needs to talk to the cluster to deploy add-ons.

```
┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│  Terraform   │────>│  AWS API      │────>│  EKS Cluster │
│  (creates)   │     │  (IAM auth)   │     │  (created)   │
└──────┬───────┘     └──────────────┘     └──────────────┘
       │                                         ^
       │  Now needs to talk to the cluster...    │
       │                                         │
       └─────────────────────────────────────────┘
         Uses: aws eks get-token (via exec plugin)
```

### Provider Configuration

```hcl
# Get the cluster info after creation
data "aws_eks_cluster" "this" {
  name = module.eks.cluster_name
}

data "aws_eks_cluster_auth" "this" {
  name = module.eks.cluster_name
}

# Configure the Kubernetes provider
provider "kubernetes" {
  host                   = data.aws_eks_cluster.this.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.this.token
}

# Configure the Helm provider (uses the same auth)
provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.this.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.this.token
  }
}
```

> **What breaks in production**: The `aws_eks_cluster_auth` data source generates a token that expires after 15 minutes. If your `terraform apply` takes longer than 15 minutes (large infrastructure), the token expires mid-apply and Helm releases fail with authentication errors. Solution: Use the `exec` plugin instead of the token data source.

### The Exec Plugin Approach (More Robust)

```hcl
provider "kubernetes" {
  host                   = data.aws_eks_cluster.this.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
  }
}

provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.this.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
    }
  }
}
```

This generates a fresh token for each API call, avoiding the expiration problem.

---

## 3. Helm Deep Dive for Terraform Engineers

If you come from a pure Terraform background, Helm can feel foreign. Here is what you need to know.

### What Helm Actually Does

Helm is a package manager for Kubernetes, the same way apt is for Ubuntu or brew is for macOS. A Helm "chart" is a package that contains:

```
my-chart/
├── Chart.yaml          # Metadata: name, version, dependencies
├── values.yaml         # Default configuration values
├── templates/          # Kubernetes manifests with Go templating
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── ingress.yaml
│   ├── configmap.yaml
│   ├── _helpers.tpl    # Template helpers (shared functions)
│   └── NOTES.txt       # Post-install message
└── charts/             # Sub-chart dependencies
```

### The Rendering Pipeline

When Helm installs a chart, it does not send the templates to Kubernetes directly. It renders them first:

```
values.yaml + overrides  ──>  Go template engine  ──>  Kubernetes YAML  ──>  kubectl apply
```

For example, this template:

```yaml
# templates/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ .Release.Name }}-{{ .Chart.Name }}
spec:
  replicas: {{ .Values.replicaCount }}
  template:
    spec:
      containers:
        - name: {{ .Chart.Name }}
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
          resources:
            requests:
              memory: {{ .Values.resources.requests.memory }}
              cpu: {{ .Values.resources.requests.cpu }}
```

With these values:

```yaml
# values.yaml
replicaCount: 3
image:
  repository: nginx
  tag: "1.25"
resources:
  requests:
    memory: "128Mi"
    cpu: "100m"
```

Renders to:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-release-my-chart
spec:
  replicas: 3
  template:
    spec:
      containers:
        - name: my-chart
          image: "nginx:1.25"
          resources:
            requests:
              memory: 128Mi
              cpu: 100m
```

### Helm Release State

When Helm installs a chart, it stores the release state as a Kubernetes Secret in the namespace where the chart is installed. This is how Helm knows what version of a chart is installed and what values were used.

```bash
# You can see Helm's state secrets
kubectl get secrets -n kube-system -l owner=helm
```

This is important because it means Helm's state lives inside Kubernetes, not inside Terraform's state. When Terraform manages a Helm release, it tracks the release metadata in its own state, but the actual release state is in Kubernetes. This dual-state situation is a source of drift.

---

## 4. The Terraform Helm Provider

### Basic Usage

```hcl
resource "helm_release" "nginx_ingress" {
  name       = "ingress-nginx"
  repository = "https://kubernetes.github.io/ingress-nginx"
  chart      = "ingress-nginx"
  version    = "4.8.3"
  namespace  = "ingress-nginx"

  create_namespace = true

  set {
    name  = "controller.replicaCount"
    value = "3"
  }

  set {
    name  = "controller.service.type"
    value = "LoadBalancer"
  }

  set {
    name  = "controller.service.annotations.service\\.beta\\.kubernetes\\.io/aws-load-balancer-type"
    value = "nlb"
  }
}
```

### The `set` vs `values` Debate

There are two ways to pass values to a Helm release in Terraform:

**Using `set` blocks** (inline):

```hcl
resource "helm_release" "prometheus" {
  # ...

  set {
    name  = "server.persistentVolume.size"
    value = "50Gi"
  }

  set {
    name  = "server.retention"
    value = "30d"
  }
}
```

**Using `values` attribute** (YAML):

```hcl
resource "helm_release" "prometheus" {
  # ...

  values = [
    yamlencode({
      server = {
        persistentVolume = {
          size = "50Gi"
        }
        retention = "30d"
      }
    })
  ]
}
```

**Or with a file:**

```hcl
resource "helm_release" "prometheus" {
  # ...

  values = [
    file("${path.module}/helm-values/prometheus.yaml")
  ]
}
```

**Recommendation**: Use `values` with `yamlencode` for most cases. It gives you:

- Terraform variable interpolation
- Proper YAML structure (no escaped dots in key names)
- Type safety (numbers stay numbers, booleans stay booleans)

Use `set` blocks only for values that need to be dynamically computed from Terraform resources:

```hcl
resource "helm_release" "aws_lb_controller" {
  # ...

  values = [
    file("${path.module}/helm-values/aws-lb-controller.yaml")
  ]

  # Dynamic values from Terraform
  set {
    name  = "clusterName"
    value = module.eks.cluster_name
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = module.aws_lb_controller_irsa.iam_role_arn
  }
}
```

### Sensitive Values

For secrets, use `set_sensitive`:

```hcl
resource "helm_release" "argocd" {
  # ...

  set_sensitive {
    name  = "configs.secret.argocdServerAdminPassword"
    value = bcrypt(var.argocd_admin_password)
  }
}
```

This prevents the value from appearing in `terraform plan` output or state file (though it is still in the Helm release secret in Kubernetes).

---

## 5. Dependency Ordering: The Hard Part

This is where most production incidents involving Terraform and Helm originate. The order in which things are created matters enormously, and Terraform's dependency graph does not always get it right.

### The Dependency Chain

```
┌──────────┐
│ VPC      │
└────┬─────┘
     │
     v
┌──────────┐
│ EKS      │ Must exist before any K8s/Helm resources
│ Cluster  │
└────┬─────┘
     │
     ├─────────────────────────────┐
     v                             v
┌──────────────┐          ┌──────────────────┐
│ Node Groups  │          │ EKS Add-ons      │
│ (must have   │          │ (CoreDNS, kube-  │
│  nodes for   │          │  proxy, VPC CNI)  │
│  pods to     │          │                   │
│  schedule)   │          │                   │
└──────┬───────┘          └────────┬──────────┘
       │                           │
       └───────────┬───────────────┘
                   │
                   v
          ┌────────────────┐
          │ CRD Controllers│  (cert-manager, AWS LB controller)
          │ Must be running│
          │ before CRDs    │
          │ are used        │
          └────────┬───────┘
                   │
                   v
          ┌────────────────┐
          │ Helm Releases  │  (your applications)
          │ that use CRDs  │
          └────────────────┘
```

### Problem: Terraform Tries to Do Everything at Once

Terraform sees that the Helm releases depend on the EKS cluster (because the Helm provider is configured with the cluster endpoint). So it creates the cluster, then immediately tries to deploy Helm charts. But:

1. The node groups might not be ready yet
2. CoreDNS might not be running yet (so DNS resolution inside the cluster fails)
3. The VPC CNI might not be configured yet (so pods cannot get IP addresses)

### Solution: Explicit Dependencies

```hcl
# Step 1: Create the cluster
module "eks" {
  source = "../../modules/eks"
  # ...
}

# Step 2: Wait for the node group to be ready
resource "aws_eks_node_group" "main" {
  cluster_name    = module.eks.cluster_name
  node_group_name = "main"
  # ...
}

# Step 3: Deploy essential add-ons first
resource "helm_release" "aws_vpc_cni" {
  depends_on = [aws_eks_node_group.main]

  name       = "aws-vpc-cni"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-vpc-cni"
  namespace  = "kube-system"
  # ...
}

resource "helm_release" "cert_manager" {
  depends_on = [aws_eks_node_group.main]

  name       = "cert-manager"
  repository = "https://charts.jetstack.io"
  chart      = "cert-manager"
  version    = "1.13.2"
  namespace  = "cert-manager"

  create_namespace = true

  set {
    name  = "installCRDs"
    value = "true"
  }
}

# Step 4: Deploy things that depend on CRDs
resource "helm_release" "aws_lb_controller" {
  depends_on = [helm_release.cert_manager]

  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"
  # ...
}

# Step 5: Deploy application charts
resource "helm_release" "application" {
  depends_on = [
    helm_release.aws_lb_controller,
    helm_release.cert_manager,
  ]

  name      = "my-application"
  chart     = "${path.module}/charts/my-application"
  namespace = "default"
  # ...
}
```

> **What breaks in production**: You deploy cert-manager and the AWS Load Balancer Controller in the same `terraform apply`. Terraform sees no dependency between them (they are both Helm releases that depend on the node group). It deploys them in parallel. The AWS LB Controller chart includes a Certificate CRD resource, but cert-manager's CRD webhook is not ready yet. The deployment fails with "no matches for kind Certificate". Fix: Add an explicit `depends_on` from the LB controller to cert-manager.

### The CRD Timing Problem

Custom Resource Definitions (CRDs) are a persistent source of pain. Here is the timeline:

```
T=0s    cert-manager Helm chart starts deploying
T=2s    CRDs are created (Certificate, Issuer, etc.)
T=3s    cert-manager pods start pulling images
T=15s   cert-manager pods are running
T=20s   cert-manager webhook is registered and ready
T=20s+  NOW you can create Certificate resources safely
```

Terraform does not wait for the webhook to be ready. It just checks that the Helm release succeeded (the chart was installed). The Helm chart succeeds when all its Kubernetes resources are created, but the cert-manager pods might still be starting.

**Solution 1: Use `wait` parameter**

```hcl
resource "helm_release" "cert_manager" {
  # ...
  wait    = true
  timeout = 600  # seconds

  # Wait for pods to actually be ready
  wait_for_jobs = true
}
```

**Solution 2: Add a time delay (last resort)**

```hcl
resource "time_sleep" "wait_for_cert_manager" {
  depends_on = [helm_release.cert_manager]

  create_duration = "30s"
}

resource "helm_release" "aws_lb_controller" {
  depends_on = [time_sleep.wait_for_cert_manager]
  # ...
}
```

This is ugly but sometimes necessary. The Kubernetes ecosystem is eventually consistent, and Terraform is not designed to wait for eventual consistency.

---

## 6. Values Management Patterns

### Pattern 1: Layered Values

Use multiple value files that override each other, from general to specific:

```
helm-values/
├── base/
│   ├── prometheus.yaml      # Defaults for all environments
│   └── grafana.yaml
├── dev/
│   ├── prometheus.yaml      # Dev overrides (smaller storage, fewer replicas)
│   └── grafana.yaml
└── production/
    ├── prometheus.yaml      # Prod overrides (large storage, HA)
    └── grafana.yaml
```

```hcl
resource "helm_release" "prometheus" {
  # ...

  values = [
    file("${path.module}/helm-values/base/prometheus.yaml"),
    file("${path.module}/helm-values/${var.environment}/prometheus.yaml"),
  ]

  # Dynamic values from Terraform resources
  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = module.prometheus_irsa.iam_role_arn
  }
}
```

The second file overrides values from the first. This keeps your base configuration DRY while allowing per-environment customization.

### Pattern 2: Computed Values with `yamlencode`

When values need to come from Terraform resources:

```hcl
resource "helm_release" "external_dns" {
  name       = "external-dns"
  repository = "https://kubernetes-sigs.github.io/external-dns"
  chart      = "external-dns"
  namespace  = "kube-system"

  values = [
    yamlencode({
      provider    = "aws"
      domainFilters = [var.domain_name]
      policy      = "sync"
      registry    = "txt"
      txtOwnerId  = module.eks.cluster_name

      serviceAccount = {
        annotations = {
          "eks.amazonaws.com/role-arn" = module.external_dns_irsa.iam_role_arn
        }
      }

      resources = {
        requests = {
          cpu    = "50m"
          memory = "64Mi"
        }
        limits = {
          memory = "128Mi"
        }
      }
    })
  ]
}
```

### Pattern 3: Values from Terraform Outputs

Pass infrastructure details into Helm charts:

```hcl
locals {
  cluster_config = {
    cluster_name       = module.eks.cluster_name
    cluster_endpoint   = module.eks.cluster_endpoint
    vpc_id             = module.vpc.vpc_id
    region             = var.region
    account_id         = data.aws_caller_identity.current.account_id
  }
}

resource "helm_release" "aws_lb_controller" {
  # ...

  values = [
    yamlencode({
      clusterName = local.cluster_config.cluster_name
      region      = local.cluster_config.region
      vpcId       = local.cluster_config.vpc_id
    })
  ]
}
```

### Pattern 4: Conditional Values

```hcl
resource "helm_release" "prometheus" {
  # ...

  values = [
    yamlencode({
      server = merge(
        {
          retention = "15d"
        },
        var.environment == "production" ? {
          replicas = 2
          persistentVolume = {
            size = "100Gi"
          }
          resources = {
            requests = { cpu = "500m", memory = "2Gi" }
            limits   = { memory = "4Gi" }
          }
        } : {
          replicas = 1
          persistentVolume = {
            size = "10Gi"
          }
          resources = {
            requests = { cpu = "100m", memory = "512Mi" }
            limits   = { memory = "1Gi" }
          }
        }
      )
    })
  ]
}
```

---

## 7. GitOps Integration

### The Spectrum of Deployment Strategies

```
TERRAFORM-MANAGED                                    GITOPS-MANAGED
      |                                                      |
      |  Terraform       Terraform       Terraform    ArgoCD |
      |  manages         manages         bootstraps   manages|
      |  everything      infra + addons  ArgoCD only  apps   |
      |                                                      |
      |  Simple but      Good balance    Best for      Pure  |
      |  fragile                         large teams   GitOps|
```

### Strategy 1: Terraform Manages Everything

Terraform deploys the cluster, add-ons, and application Helm charts.

```hcl
# Infrastructure
module "vpc" { ... }
module "eks" { ... }

# Platform add-ons
resource "helm_release" "cert_manager" { ... }
resource "helm_release" "ingress_nginx" { ... }
resource "helm_release" "prometheus" { ... }

# Applications
resource "helm_release" "api_server" { ... }
resource "helm_release" "web_frontend" { ... }
resource "helm_release" "worker" { ... }
```

**When this works**: Small teams, few services, infrequent deployments.

**When this breaks**: Application teams want to deploy independently. They do not want to make a PR to the Terraform repo and wait for approval every time they change an environment variable.

### Strategy 2: Terraform for Infra, ArgoCD for Apps (Recommended)

Terraform creates the cluster and bootstraps ArgoCD. ArgoCD takes over for application deployments.

```hcl
# Terraform creates infrastructure
module "vpc" { ... }
module "eks" { ... }

# Terraform deploys platform add-ons
resource "helm_release" "cert_manager" { ... }
resource "helm_release" "aws_lb_controller" { ... }

# Terraform bootstraps ArgoCD
resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = "5.51.4"
  namespace  = "argocd"

  create_namespace = true

  values = [
    yamlencode({
      server = {
        extraArgs = ["--insecure"]
        service = {
          type = "LoadBalancer"
        }
      }
    })
  ]
}

# Terraform creates the ArgoCD Application that points to the app repo
resource "kubernetes_manifest" "argocd_app_of_apps" {
  depends_on = [helm_release.argocd]

  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "applications"
      namespace = "argocd"
    }
    spec = {
      project = "default"
      source = {
        repoURL        = "https://github.com/mycompany/k8s-apps.git"
        targetRevision = "main"
        path           = "apps"
      }
      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = "default"
      }
      syncPolicy = {
        automated = {
          prune    = true
          selfHeal = true
        }
      }
    }
  }
}
```

```
┌─────────────────────────────────────────────────────────────┐
│                     DEPLOYMENT FLOW                          │
│                                                              │
│  ┌───────────────┐        ┌────────────────┐               │
│  │ Terraform     │        │ ArgoCD         │               │
│  │ Repo          │        │ (in cluster)   │               │
│  │               │        │                │               │
│  │ Creates:      │        │ Watches:       │               │
│  │  - VPC        │        │  - Git repo    │               │
│  │  - EKS        │        │                │               │
│  │  - Add-ons    │        │ Deploys:       │               │
│  │  - ArgoCD     │───────>│  - Apps        │               │
│  │               │        │  - ConfigMaps  │               │
│  └───────────────┘        │  - Secrets     │               │
│                           └────────┬───────┘               │
│                                    │                        │
│                                    v                        │
│                           ┌────────────────┐               │
│                           │ K8s Apps Repo  │               │
│                           │                │               │
│                           │ /apps/         │               │
│                           │   api-server/  │               │
│                           │   web-frontend/│               │
│                           │   worker/      │               │
│                           └────────────────┘               │
└─────────────────────────────────────────────────────────────┘
```

### The Boundary Rule

The critical decision is: **where does Terraform's responsibility end and GitOps begin?**

A clean boundary:

- **Terraform owns**: VPC, EKS cluster, IAM roles, node groups, and platform add-ons (cert-manager, ingress controller, monitoring stack, ArgoCD itself)
- **ArgoCD owns**: Application deployments, application-specific ConfigMaps, application CronJobs

The boundary should be at the "platform vs application" line. Infrastructure and platform services change slowly and need careful coordination. Applications change frequently and need fast iteration.

> **What breaks in production**: You use Terraform to deploy ArgoCD, but ArgoCD also manages some of the same Helm releases that Terraform deployed (like the ingress controller). Now you have two systems fighting over the same resources. ArgoCD detects "drift" (because Terraform's annotations differ from what ArgoCD expects) and tries to "fix" it. Terraform detects drift (because ArgoCD changed the resource) and tries to fix it back. They go back and forth. Solution: Never have two controllers manage the same resource. If ArgoCD manages it, remove it from Terraform (except for the initial bootstrap).

---

## 8. Debugging Helm in Terraform

When a `helm_release` resource fails, the error messages are often unhelpful. Here is a systematic approach to debugging.

### Step 1: Get the Actual Error

Terraform often wraps the Helm error in its own error message, hiding the real cause. Look for these patterns:

```
Error: failed to install chart: ...
```

The text after "failed to install chart:" is the actual Helm error.

### Step 2: Template Rendering Debug

Render the chart locally to see exactly what YAML would be sent to Kubernetes:

```bash
# Add the repo
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx

# Render the template with the same values you pass in Terraform
helm template my-release ingress-nginx/ingress-nginx \
  --version 4.8.3 \
  --namespace ingress-nginx \
  --set controller.replicaCount=3 \
  --set controller.service.type=LoadBalancer \
  > rendered.yaml

# Inspect the rendered YAML
cat rendered.yaml
```

If you use a values file in Terraform:

```bash
helm template my-release ingress-nginx/ingress-nginx \
  --version 4.8.3 \
  -f helm-values/base/ingress-nginx.yaml \
  -f helm-values/production/ingress-nginx.yaml
```

### Step 3: Dry-Run Apply

```bash
helm install my-release ingress-nginx/ingress-nginx \
  --version 4.8.3 \
  --namespace ingress-nginx \
  --dry-run --debug \
  --set controller.replicaCount=3
```

The `--debug` flag shows the computed values and the rendered templates.

### Step 4: Check Helm Release State

```bash
# List all Helm releases
helm list -A

# Get details about a specific release
helm status my-release -n ingress-nginx

# See the history (useful for debugging upgrades)
helm history my-release -n ingress-nginx

# Get the values that were used
helm get values my-release -n ingress-nginx
```

### Step 5: Check Kubernetes Events

```bash
# Broad: all events in the namespace
kubectl get events -n ingress-nginx --sort-by='.lastTimestamp'

# Specific: events for a pod
kubectl describe pod <pod-name> -n ingress-nginx
```

### Common Errors and Solutions

**Error: `timed out waiting for the condition`**

The Helm release has `wait = true` (default) and the pods did not become ready within the timeout.

```hcl
resource "helm_release" "example" {
  # ...
  timeout = 900  # Increase from default 300s

  # Or disable waiting (not recommended for production)
  # wait = false
}
```

Check why pods are not ready:

```bash
kubectl get pods -n <namespace>
kubectl describe pod <pod-name> -n <namespace>
kubectl logs <pod-name> -n <namespace>
```

**Error: `cannot re-use a name that is still in use`**

A previous failed deployment left a Helm release in a bad state.

```bash
# Check the status
helm status <release-name> -n <namespace>

# If it's in "failed" or "pending-install" state:
helm uninstall <release-name> -n <namespace>

# Then run terraform apply again
```

**Error: `no matches for kind "Certificate" in version "cert-manager.io/v1"`**

The CRD is not installed yet (dependency ordering problem -- see Section 5).

**Error: `rendered manifests contain a resource that already exists`**

Another tool (kubectl, another Helm release, or ArgoCD) already created this resource. Helm refuses to adopt existing resources. Options:

```bash
# Option 1: Delete the existing resource and let Helm create it
kubectl delete <resource> -n <namespace>

# Option 2: Annotate it so Helm adopts it
kubectl annotate <resource> meta.helm.sh/release-name=<release-name> -n <namespace>
kubectl annotate <resource> meta.helm.sh/release-namespace=<namespace> -n <namespace>
kubectl label <resource> app.kubernetes.io/managed-by=Helm -n <namespace>
```

### Step 6: Terraform State Debugging

Sometimes Terraform's state and Helm's state get out of sync:

```bash
# See what Terraform thinks the Helm release looks like
terraform state show 'helm_release.nginx_ingress'

# Force Terraform to re-read the actual state
terraform refresh

# Nuclear option: remove from Terraform state and re-import
terraform state rm 'helm_release.nginx_ingress'
terraform import 'helm_release.nginx_ingress' 'ingress-nginx/ingress-nginx'
```

---

## 9. Production Patterns and Recipes

### Recipe 1: AWS Load Balancer Controller

This is needed for Ingress resources to create ALBs/NLBs on AWS.

```hcl
# IAM Role for Service Account (IRSA)
module "aws_lb_controller_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "5.30.0"

  role_name = "${var.cluster_name}-aws-lb-controller"

  attach_load_balancer_controller_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }
}

# Helm release
resource "helm_release" "aws_lb_controller" {
  depends_on = [module.eks]

  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = "1.6.2"
  namespace  = "kube-system"

  values = [
    yamlencode({
      clusterName = module.eks.cluster_name
      region      = var.region
      vpcId       = module.vpc.vpc_id

      serviceAccount = {
        create = true
        name   = "aws-load-balancer-controller"
        annotations = {
          "eks.amazonaws.com/role-arn" = module.aws_lb_controller_irsa.iam_role_arn
        }
      }

      resources = {
        requests = { cpu = "100m", memory = "128Mi" }
        limits   = { memory = "256Mi" }
      }
    })
  ]
}
```

### Recipe 2: External DNS

Automatically creates Route53 DNS records for Ingress and Service resources.

```hcl
module "external_dns_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "5.30.0"

  role_name = "${var.cluster_name}-external-dns"

  attach_external_dns_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:external-dns"]
    }
  }
}

resource "helm_release" "external_dns" {
  depends_on = [module.eks]

  name       = "external-dns"
  repository = "https://kubernetes-sigs.github.io/external-dns"
  chart      = "external-dns"
  version    = "1.14.0"
  namespace  = "kube-system"

  values = [
    yamlencode({
      provider = "aws"
      policy   = "sync"

      domainFilters = [var.domain_name]
      txtOwnerId    = module.eks.cluster_name

      serviceAccount = {
        annotations = {
          "eks.amazonaws.com/role-arn" = module.external_dns_irsa.iam_role_arn
        }
      }

      resources = {
        requests = { cpu = "50m", memory = "64Mi" }
        limits   = { memory = "128Mi" }
      }
    })
  ]
}
```

### Recipe 3: Monitoring Stack (Prometheus + Grafana)

```hcl
resource "helm_release" "kube_prometheus_stack" {
  depends_on = [module.eks]

  name       = "kube-prometheus-stack"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  version    = "55.0.0"
  namespace  = "monitoring"

  create_namespace = true
  timeout          = 900

  values = [
    yamlencode({
      prometheus = {
        prometheusSpec = {
          retention = var.environment == "production" ? "30d" : "7d"

          storageSpec = {
            volumeClaimTemplate = {
              spec = {
                accessModes = ["ReadWriteOnce"]
                resources = {
                  requests = {
                    storage = var.environment == "production" ? "100Gi" : "20Gi"
                  }
                }
              }
            }
          }

          resources = {
            requests = { cpu = "200m", memory = "1Gi" }
            limits   = { memory = "2Gi" }
          }
        }
      }

      grafana = {
        adminPassword = var.grafana_admin_password

        ingress = {
          enabled = true
          annotations = {
            "kubernetes.io/ingress.class" = "nginx"
          }
          hosts = ["grafana.${var.domain_name}"]
        }

        persistence = {
          enabled = true
          size    = "10Gi"
        }
      }

      alertmanager = {
        alertmanagerSpec = {
          storage = {
            volumeClaimTemplate = {
              spec = {
                accessModes = ["ReadWriteOnce"]
                resources = {
                  requests = {
                    storage = "10Gi"
                  }
                }
              }
            }
          }
        }
      }
    })
  ]
}
```

### Recipe 4: Secrets Management with External Secrets Operator

```hcl
module "external_secrets_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "5.30.0"

  role_name = "${var.cluster_name}-external-secrets"

  role_policy_arns = {
    policy = aws_iam_policy.external_secrets.arn
  }

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["external-secrets:external-secrets"]
    }
  }
}

resource "aws_iam_policy" "external_secrets" {
  name = "${var.cluster_name}-external-secrets"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret",
        ]
        Resource = "arn:aws:secretsmanager:${var.region}:${data.aws_caller_identity.current.account_id}:secret:${var.cluster_name}/*"
      }
    ]
  })
}

resource "helm_release" "external_secrets" {
  depends_on = [module.eks]

  name       = "external-secrets"
  repository = "https://charts.external-secrets.io"
  chart      = "external-secrets"
  version    = "0.9.9"
  namespace  = "external-secrets"

  create_namespace = true

  values = [
    yamlencode({
      serviceAccount = {
        annotations = {
          "eks.amazonaws.com/role-arn" = module.external_secrets_irsa.iam_role_arn
        }
      }
    })
  ]
}
```

---

## 10. Anti-Patterns

### Anti-Pattern 1: Managing Individual Kubernetes Resources with Terraform

```hcl
# BAD: Using the kubernetes provider for application resources
resource "kubernetes_deployment" "api" {
  metadata {
    name      = "api-server"
    namespace = "default"
  }
  spec {
    replicas = 3
    # ... 80 lines of deployment spec
  }
}

resource "kubernetes_service" "api" {
  metadata {
    name      = "api-server"
    namespace = "default"
  }
  spec {
    # ... 30 lines of service spec
  }
}
```

This is painful because Kubernetes YAML mapped to HCL is verbose and hard to read. Use Helm charts for application deployments. The Kubernetes provider is appropriate for one-off resources like namespaces, RBAC, or CRDs.

### Anti-Pattern 2: Not Pinning Chart Versions

```hcl
# BAD: No version pinned
resource "helm_release" "nginx" {
  name       = "ingress-nginx"
  repository = "https://kubernetes.github.io/ingress-nginx"
  chart      = "ingress-nginx"
  # version  = ???  <-- Missing!
}
```

Without a version, Helm installs the latest version. The next `terraform apply` might upgrade the chart with breaking changes.

### Anti-Pattern 3: `wait = false` in Production

```hcl
# DANGEROUS in production
resource "helm_release" "critical_service" {
  # ...
  wait = false  # Terraform "succeeds" even if pods are crashing
}
```

With `wait = false`, Terraform marks the resource as created as soon as Kubernetes accepts the manifests. The pods might be in CrashLoopBackOff, but Terraform reports success. Downstream resources that depend on this service will fail in confusing ways.

### Anti-Pattern 4: Storing Large Values in Terraform State

```hcl
# BAD: Embedding a large YAML file as a value
resource "helm_release" "grafana" {
  # ...
  values = [
    file("${path.module}/dashboards/all-200-dashboards.json")  # 50MB file
  ]
}
```

This bloats the Terraform state file. Use ConfigMaps mounted as volumes, or use Grafana's API to provision dashboards.

### Anti-Pattern 5: Ignoring `force_update` and `replace`

```hcl
# This can cause surprise replacements
resource "helm_release" "example" {
  # ...
  replace      = true  # Deletes and recreates the release on failure
  force_update = true  # Forces an update even if nothing changed
}
```

Both of these can cause service disruptions. `replace = true` deletes the entire release before reinstalling, which means downtime. Use them only for non-critical development environments.

---

## 11. Test Yourself

**Question 1**: You run `terraform apply` and a `helm_release` resource fails with "timed out waiting for the condition." The pods are in `ImagePullBackOff` state. What happened and how do you fix it?

**Answer**: The container image cannot be pulled. Common causes: (1) The image tag does not exist in the registry. (2) The node does not have permission to pull from the registry (ECR IAM policy missing). (3) The registry is in a different region or account. Fix: Check `kubectl describe pod` for the exact error, verify the image exists, and ensure the node group's IAM role has `ecr:GetDownloadUrlForLayer` and `ecr:BatchGetImage` permissions.

**Question 2**: You have Terraform deploying cert-manager and an application chart that uses a Certificate CRD. The first `terraform apply` works fine. On the second apply, cert-manager is upgraded, and the application chart fails with "no matches for kind Certificate." What is happening?

**Answer**: The cert-manager upgrade might temporarily unregister its webhook while the new pods start. During this window, the Kubernetes API server cannot validate Certificate resources. If Terraform tries to deploy the application chart during this window, it fails. Fix: Add an explicit `depends_on` and consider setting `wait = true` with a sufficient timeout on the cert-manager release.

**Question 3**: You use `data "aws_eks_cluster_auth"` to get a token for the Kubernetes and Helm providers. Your `terraform apply` takes 20 minutes. Halfway through, all Helm releases fail with authentication errors. Why?

**Answer**: The EKS auth token expires after 15 minutes. Since the token is fetched once at the start of the apply and reused, it expires before all resources are created. Fix: Use the `exec` plugin approach instead, which generates a fresh token for each API call.

**Question 4**: You deploy ArgoCD via Terraform. You also use Terraform to deploy the ingress-nginx controller. ArgoCD then detects that the ingress-nginx resources have "drifted" and tries to sync them. What is the problem and how do you solve it?

**Answer**: Two controllers (Terraform and ArgoCD) are managing the same resources. Each one thinks the other's changes are drift. Solution: Choose one owner per resource. If ArgoCD manages ingress-nginx, remove the Terraform `helm_release` for it and let ArgoCD deploy it. Terraform should only bootstrap ArgoCD itself.

**Question 5**: You want to pass a database password from AWS Secrets Manager into a Helm chart. What is the most secure approach?

**Answer**: Do not pass the password through Terraform at all. Instead: (1) Store the secret in AWS Secrets Manager. (2) Deploy the External Secrets Operator via Terraform. (3) Create an ExternalSecret resource that syncs the secret from AWS Secrets Manager into a Kubernetes Secret. (4) Mount the Kubernetes Secret into your application pods. This way, the password never appears in Terraform state or Helm values.

**Question 6**: Your `helm_release` resource shows changes on every `terraform plan`, even though you have not changed anything. The plan shows `values` being updated. Why?

**Answer**: Common causes: (1) You are using `yamlencode()` and the key ordering changes between runs (unlikely with modern Terraform but possible). (2) You have a dynamic value that changes each plan (like a timestamp or a data source that returns different values). (3) The Helm chart's `values.yaml` has default values that differ from what Terraform stored. Fix: Use `ignore_changes` on the `values` attribute as a last resort, but first investigate why the values are changing.

**Question 7**: You need to deploy a Helm chart that requires a CRD to be installed first, but the CRD is installed by a different Helm chart. Both charts are managed by Terraform. How do you ensure correct ordering?

**Answer**: Add an explicit `depends_on` from the chart that uses the CRD to the chart that installs the CRD. Also set `wait = true` on the CRD-installing chart so that Terraform waits for its pods (including the admission webhook) to be ready before proceeding.

**Question 8**: You are using the `kubernetes_manifest` resource to create an ArgoCD Application. The first `terraform apply` fails because the ArgoCD CRD does not exist yet. How do you fix this?

**Answer**: Add `depends_on = [helm_release.argocd]` to the `kubernetes_manifest` resource. The `kubernetes_manifest` resource requires the CRD to exist at plan time (not just apply time), so you may need to: (1) Apply in two stages (first apply creates ArgoCD, second apply creates the Application), or (2) Use `helm_release` with a local chart that contains the Application resource instead of `kubernetes_manifest`.

**Question 9**: You run `terraform destroy` and the `helm_release` resource fails to delete because the namespace is stuck in Terminating state. What causes this and how do you resolve it?

**Answer**: A namespace gets stuck in Terminating when it contains resources with finalizers that cannot be processed (often because the controller that handles the finalizer has already been deleted). Common culprit: deleting cert-manager before deleting Certificate resources. Fix: (1) Manually remove the finalizer from the stuck resources using `kubectl edit` or `kubectl patch`. (2) Design your destroy order carefully -- destroy application resources before destroying the controllers that manage them.

**Question 10**: You want to upgrade an EKS cluster from 1.27 to 1.28 while also upgrading several Helm chart versions. Should you do this in one `terraform apply`? Why or why not?

**Answer**: No. Upgrading the EKS cluster version changes the Kubernetes API server, which temporarily disrupts the cluster. If Terraform then immediately tries to upgrade Helm charts on a disrupted cluster, the Helm operations will fail. Upgrade in stages: (1) Upgrade the EKS cluster version and apply. (2) Verify the cluster is healthy. (3) Upgrade Helm chart versions and apply. Also check Helm chart compatibility with the new Kubernetes version before upgrading.

---

> **Key Takeaway**: The intersection of Terraform, Helm, and Kubernetes is where most production complexity lives. Master dependency ordering, choose a clean boundary between Terraform-managed and GitOps-managed resources, and always pin your chart versions. When debugging, work from the inside out: check Kubernetes events first, then Helm release state, then Terraform state.
