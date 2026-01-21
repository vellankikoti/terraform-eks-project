# 04 - AWS EKS Production Setup: The Complete Guide

> **Goal**: Build a production-grade EKS cluster that can serve millions of users, with all critical add-ons, security best practices, and real Terraform code.

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [VPC Design](#2-vpc-design)
3. [IAM Best Practices](#3-iam-best-practices)
4. [EKS Cluster Setup](#4-eks-cluster-setup)
5. [Node Groups and Compute](#5-node-groups-and-compute)
6. [Kubernetes Add-ons](#6-kubernetes-add-ons)
7. [Complete Implementation](#7-complete-implementation)

---

## 1. Architecture Overview

### What We're Building

```
┌─────────────────────────────────────────────────────────────┐
│                         AWS ACCOUNT                          │
│                                                               │
│  ┌────────────────────────────────────────────────────────┐ │
│  │                  VPC (10.0.0.0/16)                     │ │
│  │                                                         │ │
│  │  ┌──────────────────┐      ┌──────────────────┐       │ │
│  │  │  us-east-1a      │      │  us-east-1b      │       │ │
│  │  │                  │      │                  │       │ │
│  │  │ ┌──────────────┐ │      │ ┌──────────────┐ │       │ │
│  │  │ │Public Subnet │ │      │ │Public Subnet │ │       │ │
│  │  │ │10.0.0.0/24   │ │      │ │10.0.1.0/24   │ │       │ │
│  │  │ │              │ │      │ │              │ │       │ │
│  │  │ │ [NAT GW]     │ │      │ │ [NAT GW]     │ │       │ │
│  │  │ └──────────────┘ │      │ └──────────────┘ │       │ │
│  │  │                  │      │                  │       │ │
│  │  │ ┌──────────────┐ │      │ ┌──────────────┐ │       │ │
│  │  │ │Private Subnet│ │      │ │Private Subnet│ │       │ │
│  │  │ │10.0.10.0/24  │ │      │ │10.0.11.0/24  │ │       │ │
│  │  │ │              │ │      │ │              │ │       │ │
│  │  │ │ [EKS Nodes]  │ │      │ │ [EKS Nodes]  │ │       │ │
│  │  │ │ [RDS]        │ │      │ │ [RDS Standby]│ │       │ │
│  │  │ └──────────────┘ │      │ └──────────────┘ │       │ │
│  │  └──────────────────┘      └──────────────────┘       │ │
│  │                                                         │ │
│  │            ┌─────────────────────────┐                 │ │
│  │            │   EKS Control Plane     │                 │ │
│  │            │   (AWS Managed)         │                 │ │
│  │            └─────────────────────────┘                 │ │
│  └────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

### Key Design Decisions

#### 1. Multi-AZ for High Availability
- Subnets in 2+ availability zones
- Node groups distributed across AZs
- Database replicas in different AZs

#### 2. Public + Private Subnets
- **Public subnets**: NAT Gateways, Load Balancers
- **Private subnets**: EKS nodes, databases (no direct internet access)

#### 3. NAT Gateway per AZ
- Cost: ~$35/month per NAT Gateway
- Benefit: No single point of failure
- Alternative (cheaper): Single NAT Gateway (but reduces availability)

#### 4. Private EKS Cluster Endpoint
- Control plane accessible only from within VPC (more secure)
- Can enable public endpoint for kubectl access (with restricted CIDR)

---

## 2. VPC Design

### CIDR Planning

**VPC CIDR**: `10.0.0.0/16` (65,536 IPs)

| Subnet Type | AZ | CIDR | IPs Available | Purpose |
|-------------|----|----- |---------------|---------|
| Public | us-east-1a | 10.0.0.0/24 | 251 | NAT GW, ALB |
| Public | us-east-1b | 10.0.1.0/24 | 251 | NAT GW, ALB |
| Private | us-east-1a | 10.0.10.0/24 | 251 | EKS nodes |
| Private | us-east-1b | 10.0.11.0/24 | 251 | EKS nodes |
| Private | us-east-1a | 10.0.20.0/24 | 251 | Databases |
| Private | us-east-1b | 10.0.21.0/24 | 251 | Databases |

**Why /24 subnets?**
- /24 = 256 IPs (251 usable, AWS reserves 5)
- Enough for ~250 EKS nodes per subnet
- Room for growth

### Subnet Tagging (Critical for EKS)

EKS requires specific tags to discover subnets:

```hcl
# Public subnet tags
tags = {
  "kubernetes.io/role/elb" = "1"  # For public load balancers
  "kubernetes.io/cluster/${var.cluster_name}" = "shared"
}

# Private subnet tags
tags = {
  "kubernetes.io/role/internal-elb" = "1"  # For internal load balancers
  "kubernetes.io/cluster/${var.cluster_name}" = "shared"
}
```

**Without these tags:** AWS Load Balancer Controller won't find subnets.

---

## 3. IAM Best Practices

### IRSA (IAM Roles for Service Accounts)

**Old way (bad):**
- Assign IAM role to EC2 instance
- All pods on that instance inherit the same permissions
- No least privilege

**IRSA (good):**
- Each Kubernetes ServiceAccount gets its own IAM role
- Fine-grained permissions per pod
- Secure and auditable

**How it works:**

```
┌────────────────┐
│  Kubernetes    │
│  Pod           │
│  ServiceAccount│
│  "my-app-sa"   │
└───────┬────────┘
        │ OIDC token
        ↓
┌────────────────┐
│  IAM Role      │
│  "my-app-role" │
│  (AssumeRole   │
│   with OIDC)   │
└───────┬────────┘
        │
        ↓
┌────────────────┐
│  AWS API       │
│  (S3, DynamoDB,│
│   etc.)        │
└────────────────┘
```

**Setup:**

1. Enable IRSA on EKS cluster (automatic with `enable_irsa = true`)
2. Create IAM role with trust policy for OIDC provider
3. Create Kubernetes ServiceAccount with annotation
4. Assign ServiceAccount to pod

**Example (we'll see full code later):**

```hcl
# IAM role
resource "aws_iam_role" "my_app" {
  name = "my-app-role"

  assume_role_policy = jsonencode({
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.eks.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${aws_iam_openid_connect_provider.eks.url}:sub" = "system:serviceaccount:default:my-app-sa"
        }
      }
    }]
  })
}
```

```yaml
# Kubernetes ServiceAccount
apiVersion: v1
kind: ServiceAccount
metadata:
  name: my-app-sa
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::123456789:role/my-app-role
```

---

## 4. EKS Cluster Setup

### Control Plane Configuration

```hcl
resource "aws_eks_cluster" "main" {
  name     = "production-eks"
  role_arn = aws_iam_role.eks_cluster.arn
  version  = "1.28"  # Use latest stable version

  vpc_config {
    subnet_ids = concat(
      aws_subnet.private[*].id,
      aws_subnet.public[*].id
    )

    endpoint_private_access = true   # Nodes access via private VPC
    endpoint_public_access  = true   # kubectl access from internet
    public_access_cidrs     = ["1.2.3.4/32"]  # Restrict to your IP

    security_group_ids = [aws_security_group.eks_cluster.id]
  }

  # Enable control plane logging (critical for debugging)
  enabled_cluster_log_types = [
    "api",
    "audit",
    "authenticator",
    "controllerManager",
    "scheduler"
  ]

  # Encryption at rest (compliance requirement)
  encryption_config {
    provider {
      key_arn = aws_kms_key.eks.arn
    }
    resources = ["secrets"]
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy
  ]

  tags = {
    Environment = "production"
  }
}
```

### Cluster IAM Role

```hcl
resource "aws_iam_role" "eks_cluster" {
  name = "eks-cluster-role"

  assume_role_policy = jsonencode({
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "eks.amazonaws.com"
      }
    }]
    Version = "2012-10-17"
  })
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster.name
}
```

### OIDC Provider (for IRSA)

```hcl
data "tls_certificate" "eks" {
  url = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.main.identity[0].oidc[0].issuer

  tags = {
    Name = "${aws_eks_cluster.main.name}-irsa"
  }
}
```

---

## 5. Node Groups and Compute

### Managed Node Groups

**Why managed node groups?**
- AWS handles updates and patching
- Simplified lifecycle management
- Integration with EKS control plane

```hcl
resource "aws_eks_node_group" "general" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "general-purpose"
  node_role_arn   = aws_iam_role.eks_nodes.arn

  subnet_ids = aws_subnet.private[*].id

  # Scaling configuration
  scaling_config {
    desired_size = 3
    max_size     = 10
    min_size     = 2
  }

  # Update configuration (rolling updates)
  update_config {
    max_unavailable = 1  # Update 1 node at a time
  }

  # Instance types
  instance_types = ["t3.large"]

  # Disk size
  disk_size = 50  # GB

  # Labels (for pod scheduling)
  labels = {
    role = "general"
  }

  # Taints (optional, for dedicated workloads)
  # taint {
  #   key    = "dedicated"
  #   value  = "gpu"
  #   effect = "NO_SCHEDULE"
  # }

  # Tags propagated to EC2 instances
  tags = {
    Name = "eks-general-node"
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_worker_node_policy,
    aws_iam_role_policy_attachment.eks_cni_policy,
    aws_iam_role_policy_attachment.eks_container_registry_policy,
  ]

  lifecycle {
    create_before_destroy = true
    ignore_changes        = [scaling_config[0].desired_size]  # Let Cluster Autoscaler manage this
  }
}
```

### Node IAM Role

```hcl
resource "aws_iam_role" "eks_nodes" {
  name = "eks-node-role"

  assume_role_policy = jsonencode({
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
    Version = "2012-10-17"
  })
}

# Required policies for nodes
resource "aws_iam_role_policy_attachment" "eks_worker_node_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks_nodes.name
}

resource "aws_iam_role_policy_attachment" "eks_cni_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks_nodes.name
}

resource "aws_iam_role_policy_attachment" "eks_container_registry_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks_nodes.name
}
```

### Launch Template (Advanced Configuration)

For advanced scenarios (custom AMI, bootstrap scripts):

```hcl
resource "aws_launch_template" "eks_nodes" {
  name_prefix = "eks-node-"
  description = "Launch template for EKS nodes"

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size           = 100
      volume_type           = "gp3"
      iops                  = 3000
      throughput            = 125
      encrypted             = true
      kms_key_id            = aws_kms_key.ebs.arn
      delete_on_termination = true
    }
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"  # IMDSv2 required (security)
    http_put_response_hop_limit = 1
  }

  monitoring {
    enabled = true
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "eks-node"
    }
  }

  user_data = base64encode(templatefile("${path.module}/user_data.sh", {
    cluster_name        = aws_eks_cluster.main.name
    cluster_endpoint    = aws_eks_cluster.main.endpoint
    cluster_ca          = aws_eks_cluster.main.certificate_authority[0].data
  }))
}
```

---

## 6. Kubernetes Add-ons

### Critical Add-ons (Must-Have)

1. **AWS Load Balancer Controller** - Manages ALB/NLB
2. **EBS CSI Driver** - Persistent volumes
3. **Cluster Autoscaler / Karpenter** - Auto-scaling nodes
4. **Metrics Server** - Resource metrics
5. **CoreDNS** - DNS resolution

### Observability Add-ons

6. **Prometheus** - Metrics collection
7. **Grafana** - Dashboards
8. **OpenTelemetry Collector** - Traces and metrics
9. **Fluent Bit** - Log forwarding

### Operational Add-ons

10. **External DNS** - Automatic DNS records
11. **Cert-Manager** - TLS certificate automation
12. **Reloader** - Auto-restart pods on ConfigMap/Secret changes
13. **ArgoCD** - GitOps deployments

---

### Add-on 1: AWS Load Balancer Controller

**What it does:** Provisions ALB/NLB when you create Kubernetes Ingress or LoadBalancer Service.

**Why it's critical:** Without it, EKS can't create load balancers.

**Installation:**

See full code in [terraform/modules/addons/aws-load-balancer-controller/](../terraform/modules/addons/aws-load-balancer-controller/)

**Key points:**

```hcl
resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"
  version    = "1.6.2"

  set {
    name  = "clusterName"
    value = var.cluster_name
  }

  set {
    name  = "serviceAccount.create"
    value = "true"
  }

  set {
    name  = "serviceAccount.name"
    value = "aws-load-balancer-controller"
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.aws_load_balancer_controller.arn
  }
}
```

**IAM role (IRSA):**

```hcl
resource "aws_iam_role" "aws_load_balancer_controller" {
  name = "${var.cluster_name}-aws-load-balancer-controller"

  assume_role_policy = jsonencode({
    Statement = [{
      Action = "sts:AssumeRoleWithWebIdentity"
      Effect = "Allow"
      Principal = {
        Federated = var.oidc_provider_arn
      }
      Condition = {
        StringEquals = {
          "${var.oidc_provider}:sub" = "system:serviceaccount:kube-system:aws-load-balancer-controller"
        }
      }
    }]
  })
}

# Attach policy (download from AWS docs)
resource "aws_iam_role_policy" "aws_load_balancer_controller" {
  name = "AWSLoadBalancerControllerPolicy"
  role = aws_iam_role.aws_load_balancer_controller.id

  policy = file("${path.module}/iam_policy.json")
}
```

---

### Add-on 2: EBS CSI Driver

**What it does:** Allows pods to use EBS volumes as persistent storage.

**Why it's critical:** Without it, PersistentVolumeClaims won't work.

**Installation:**

```hcl
resource "aws_eks_addon" "ebs_csi_driver" {
  cluster_name             = var.cluster_name
  addon_name               = "aws-ebs-csi-driver"
  addon_version            = "v1.25.0-eksbuild.1"
  service_account_role_arn = aws_iam_role.ebs_csi_driver.arn

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "PRESERVE"
}
```

**IAM role:**

```hcl
resource "aws_iam_role" "ebs_csi_driver" {
  name = "${var.cluster_name}-ebs-csi-driver"

  assume_role_policy = jsonencode({
    Statement = [{
      Action = "sts:AssumeRoleWithWebIdentity"
      Effect = "Allow"
      Principal = {
        Federated = var.oidc_provider_arn
      }
      Condition = {
        StringEquals = {
          "${var.oidc_provider}:sub" = "system:serviceaccount:kube-system:ebs-csi-controller-sa"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ebs_csi_driver" {
  role       = aws_iam_role.ebs_csi_driver.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}
```

---

### Add-on 3: Cluster Autoscaler

**What it does:** Automatically scales node groups based on pod resource requests.

**How it works:**

```
1. Pod can't be scheduled (insufficient CPU/memory)
2. Cluster Autoscaler sees pending pod
3. Adds nodes to node group
4. Pod gets scheduled
5. If nodes are underutilized, scales down
```

**Installation:**

```hcl
resource "helm_release" "cluster_autoscaler" {
  name       = "cluster-autoscaler"
  repository = "https://kubernetes.github.io/autoscaler"
  chart      = "cluster-autoscaler"
  namespace  = "kube-system"
  version    = "9.29.3"

  set {
    name  = "autoDiscovery.clusterName"
    value = var.cluster_name
  }

  set {
    name  = "awsRegion"
    value = var.aws_region
  }

  set {
    name  = "rbac.serviceAccount.create"
    value = "true"
  }

  set {
    name  = "rbac.serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.cluster_autoscaler.arn
  }

  set {
    name  = "extraArgs.balance-similar-node-groups"
    value = "true"
  }

  set {
    name  = "extraArgs.skip-nodes-with-system-pods"
    value = "false"
  }
}
```

**IAM role:**

```hcl
resource "aws_iam_role" "cluster_autoscaler" {
  name = "${var.cluster_name}-cluster-autoscaler"

  assume_role_policy = jsonencode({
    Statement = [{
      Action = "sts:AssumeRoleWithWebIdentity"
      Effect = "Allow"
      Principal = {
        Federated = var.oidc_provider_arn
      }
      Condition = {
        StringEquals = {
          "${var.oidc_provider}:sub" = "system:serviceaccount:kube-system:cluster-autoscaler"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "cluster_autoscaler" {
  name = "ClusterAutoscalerPolicy"
  role = aws_iam_role.cluster_autoscaler.id

  policy = jsonencode({
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "autoscaling:DescribeAutoScalingGroups",
          "autoscaling:DescribeAutoScalingInstances",
          "autoscaling:DescribeLaunchConfigurations",
          "autoscaling:DescribeScalingActivities",
          "autoscaling:DescribeTags",
          "ec2:DescribeInstanceTypes",
          "ec2:DescribeLaunchTemplateVersions"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "autoscaling:SetDesiredCapacity",
          "autoscaling:TerminateInstanceInAutoScalingGroup"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "autoscaling:ResourceTag/kubernetes.io/cluster/${var.cluster_name}" = "owned"
          }
        }
      }
    ]
  })
}
```

---

### Add-on 4: Metrics Server

**What it does:** Collects resource metrics (CPU, memory) from nodes and pods.

**Why it's critical:** Required for `kubectl top` and Horizontal Pod Autoscaler.

**Installation:**

```hcl
resource "helm_release" "metrics_server" {
  name       = "metrics-server"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  namespace  = "kube-system"
  version    = "3.11.0"

  set {
    name  = "args[0]"
    value = "--kubelet-preferred-address-types=InternalIP"
  }
}
```

---

### Add-on 5: External DNS

**What it does:** Automatically creates Route53 DNS records for Ingress and Service resources.

**Example:**

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-app
  annotations:
    external-dns.alpha.kubernetes.io/hostname: myapp.example.com
spec:
  rules:
  - host: myapp.example.com
    http:
      paths:
      - path: /
        backend:
          service:
            name: my-app
            port:
              number: 80
```

**External DNS automatically creates:** `myapp.example.com` → ALB DNS name

**Installation:** See [terraform/modules/addons/external-dns/](../terraform/modules/addons/external-dns/)

---

### Add-on 6: Cert-Manager

**What it does:** Automatically provisions and renews TLS certificates (Let's Encrypt).

**Installation:**

```hcl
resource "helm_release" "cert_manager" {
  name       = "cert-manager"
  repository = "https://charts.jetstack.io"
  chart      = "cert-manager"
  namespace  = "cert-manager"
  version    = "v1.13.2"

  create_namespace = true

  set {
    name  = "installCRDs"
    value = "true"
  }
}
```

**Usage:**

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: admin@example.com
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - http01:
        ingress:
          class: alb
```

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-app
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
spec:
  tls:
  - hosts:
    - myapp.example.com
    secretName: myapp-tls
  rules:
  - host: myapp.example.com
    ...
```

---

## 7. Complete Implementation

Now let's build the complete, production-ready modules.

### Directory Structure

```
terraform/
├── modules/
│   ├── vpc/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   ├── eks/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   └── addons/
│       ├── aws-load-balancer-controller/
│       ├── cluster-autoscaler/
│       └── ...
└── environments/
    └── dev/
        ├── main.tf
        ├── backend.tf
        ├── variables.tf
        └── terraform.tfvars
```

We'll create the actual Terraform modules next. Let's start with VPC and EKS.

---

## Summary Checklist

**Infrastructure:**
- ✅ Multi-AZ VPC with public and private subnets
- ✅ NAT Gateways for high availability
- ✅ Proper subnet tagging for EKS
- ✅ EKS cluster with control plane logging
- ✅ Managed node groups with auto-scaling
- ✅ IRSA enabled (OIDC provider)

**Security:**
- ✅ Private subnets for nodes
- ✅ Encryption at rest (KMS)
- ✅ IMDSv2 required
- ✅ Least privilege IAM roles (IRSA)
- ✅ Security groups with minimal access

**Add-ons (Critical):**
- ✅ AWS Load Balancer Controller
- ✅ EBS CSI Driver
- ✅ Cluster Autoscaler
- ✅ Metrics Server
- ✅ External DNS
- ✅ Cert-Manager

**Next Steps:**
- Build remaining add-ons (Prometheus, Grafana, etc.)
- Set up CI/CD with ArgoCD
- Configure observability (OpenTelemetry, Splunk)

---

**Next:** Let's create the actual Terraform modules (VPC, EKS, Add-ons).
