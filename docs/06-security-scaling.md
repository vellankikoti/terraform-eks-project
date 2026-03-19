# 06 - Security, Scaling & Reliability: Production-Grade EKS

> **Goal**: Build an EKS platform that is secure by default, scales automatically under load, survives failures gracefully, and does not drain your AWS bill.

---

## Table of Contents

1. [IAM Deep Dive](#1-iam-deep-dive)
2. [EKS Security Layers](#2-eks-security-layers)
3. [Secrets Management](#3-secrets-management)
4. [Karpenter vs Cluster Autoscaler](#4-karpenter-vs-cluster-autoscaler)
5. [Spot Instances Strategy](#5-spot-instances-strategy)
6. [Cost Optimization](#6-cost-optimization)
7. [Reliability Patterns](#7-reliability-patterns)
8. [Multi-Account Strategy](#8-multi-account-strategy)
9. [Putting It All Together](#9-putting-it-all-together)
10. [Test Yourself](#10-test-yourself)

---

## 1. IAM Deep Dive

IAM is the foundation of AWS security. Every misconfiguration here cascades into vulnerabilities everywhere else. For EKS, IAM is triply important because you have AWS-level permissions, Kubernetes-level permissions, and the bridge between them (IRSA).

### The Three IAM Layers in EKS

```
┌─────────────────────────────────────────────────────────────┐
│                    IAM IN EKS                                │
│                                                              │
│  Layer 1: CLUSTER IAM ROLE                                   │
│  ┌─────────────────────────────────────────────────────┐    │
│  │ "Who can the EKS control plane pretend to be?"       │    │
│  │                                                       │    │
│  │ - Manages ENIs for pod networking                     │    │
│  │ - Creates security groups                             │    │
│  │ - Writes to CloudWatch Logs                           │    │
│  │ - Policy: AmazonEKSClusterPolicy                      │    │
│  └─────────────────────────────────────────────────────┘    │
│                                                              │
│  Layer 2: NODE GROUP IAM ROLE                                │
│  ┌─────────────────────────────────────────────────────┐    │
│  │ "What can the EC2 instances (worker nodes) do?"       │    │
│  │                                                       │    │
│  │ - Pull container images from ECR                      │    │
│  │ - Register with the EKS cluster                       │    │
│  │ - Policy: AmazonEKSWorkerNodePolicy                   │    │
│  │ - Policy: AmazonEKS_CNI_Policy                        │    │
│  │ - Policy: AmazonEC2ContainerRegistryReadOnly          │    │
│  └─────────────────────────────────────────────────────┘    │
│                                                              │
│  Layer 3: POD-LEVEL IAM (IRSA)                               │
│  ┌─────────────────────────────────────────────────────┐    │
│  │ "What can individual pods do?"                        │    │
│  │                                                       │    │
│  │ - Pod A can read from S3 bucket X                     │    │
│  │ - Pod B can write to DynamoDB table Y                 │    │
│  │ - Pod C can send messages to SQS queue Z              │    │
│  │ - Each pod gets ONLY the permissions it needs         │    │
│  └─────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────┘
```

### IRSA: IAM Roles for Service Accounts

IRSA is the mechanism that lets Kubernetes pods assume specific IAM roles. Without IRSA, all pods on a node share the node's IAM role -- which means every pod can do everything the node can do. This is the equivalent of giving every employee in your company the CEO's access badge.

**How IRSA works:**

```
┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│  Pod starts  │────>│  K8s Service │────>│  AWS STS     │
│  with SA     │     │  Account has │     │  AssumeRole  │
│  annotation  │     │  OIDC token  │     │  WithWebId   │
└──────────────┘     └──────────────┘     └──────┬───────┘
                                                  │
                                                  v
                                          ┌──────────────┐
                                          │  IAM Role    │
                                          │  with policy │
                                          │  for S3 only │
                                          └──────────────┘
```

1. You create an IAM role with a trust policy that says "this Kubernetes service account in this namespace can assume this role."
2. You annotate the Kubernetes ServiceAccount with the IAM role ARN.
3. When a pod starts with that ServiceAccount, the EKS Pod Identity webhook injects AWS credentials into the pod.
4. The pod can now call AWS APIs with the permissions defined in the IAM role.

**Terraform implementation:**

```hcl
# Step 1: Create the OIDC provider (usually done once per cluster)
data "tls_certificate" "eks" {
  url = module.eks.cluster_oidc_issuer_url
}

resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]
  url             = module.eks.cluster_oidc_issuer_url
}

# Step 2: Create an IAM role for a specific service
resource "aws_iam_role" "s3_reader" {
  name = "${var.cluster_name}-s3-reader"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.eks.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:sub" = "system:serviceaccount:my-namespace:my-service-account"
            "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })
}

# Step 3: Attach a policy
resource "aws_iam_role_policy" "s3_reader" {
  name = "s3-read-access"
  role = aws_iam_role.s3_reader.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket",
        ]
        Resource = [
          "arn:aws:s3:::${var.data_bucket_name}",
          "arn:aws:s3:::${var.data_bucket_name}/*",
        ]
      }
    ]
  })
}

# Step 4: Create the Kubernetes ServiceAccount
resource "kubernetes_service_account" "s3_reader" {
  metadata {
    name      = "my-service-account"
    namespace = "my-namespace"

    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.s3_reader.arn
    }
  }
}
```

> **What breaks in production**: You set up IRSA correctly, but your pods still get "Access Denied" errors. The three most common causes: (1) The namespace or service account name in the trust policy does not match the actual pod's service account. (2) The OIDC provider thumbprint is wrong (AWS sometimes changes their certificate chain). (3) The pod was created before the ServiceAccount annotation was added -- you need to restart the pod to pick up the new credentials.

### Least Privilege in Practice

The principle of least privilege says: give every entity only the permissions it needs, nothing more. In practice, this is hard because AWS has thousands of IAM actions. Here is a practical approach:

1. **Start with AWS managed policies** for common patterns (like `AmazonS3ReadOnlyAccess`).
2. **Narrow the resources** to specific ARNs (not `*`).
3. **Use CloudTrail + IAM Access Analyzer** to find unused permissions after 30 days.
4. **Remove unused permissions** based on actual usage data.

```hcl
# BAD: Too broad
resource "aws_iam_role_policy" "bad" {
  policy = jsonencode({
    Statement = [{
      Effect   = "Allow"
      Action   = "s3:*"           # All S3 actions
      Resource = "*"              # All S3 buckets in the account
    }]
  })
}

# GOOD: Least privilege
resource "aws_iam_role_policy" "good" {
  policy = jsonencode({
    Statement = [{
      Effect = "Allow"
      Action = [
        "s3:GetObject",          # Only read
      ]
      Resource = [
        "arn:aws:s3:::my-specific-bucket/prefix/*"  # Only one prefix
      ]
    }]
  })
}
```

---

## 2. EKS Security Layers

Security in EKS is not a single feature -- it is a stack of layers. Each layer catches what the previous layer missed.

```
┌─────────────────────────────────────────────────────┐
│ Layer 7: APPLICATION SECURITY                        │
│   Code scanning, dependency checking, WAF            │
├─────────────────────────────────────────────────────┤
│ Layer 6: RUNTIME SECURITY                            │
│   Falco, GuardDuty for EKS, eBPF monitoring         │
├─────────────────────────────────────────────────────┤
│ Layer 5: POD SECURITY                                │
│   Pod Security Standards, OPA/Kyverno policies       │
├─────────────────────────────────────────────────────┤
│ Layer 4: IMAGE SECURITY                              │
│   ECR scanning, Trivy, signed images                 │
├─────────────────────────────────────────────────────┤
│ Layer 3: NETWORK SECURITY                            │
│   Network Policies, security groups, private subnets │
├─────────────────────────────────────────────────────┤
│ Layer 2: IDENTITY & ACCESS                           │
│   IRSA, RBAC, aws-auth ConfigMap, OIDC               │
├─────────────────────────────────────────────────────┤
│ Layer 1: CLUSTER SECURITY                            │
│   Private endpoint, envelope encryption, audit logs  │
└─────────────────────────────────────────────────────┘
```

### Layer 1: Cluster Security

```hcl
resource "aws_eks_cluster" "main" {
  name     = var.cluster_name
  role_arn = aws_iam_role.cluster.arn
  version  = "1.28"

  vpc_config {
    subnet_ids              = var.private_subnet_ids
    endpoint_private_access = true
    endpoint_public_access  = true   # Set to false for maximum security
    public_access_cidrs     = var.allowed_cidrs  # Restrict if public

    security_group_ids = [aws_security_group.cluster.id]
  }

  # Envelope encryption for secrets in etcd
  encryption_config {
    provider {
      key_arn = aws_kms_key.eks.arn
    }
    resources = ["secrets"]
  }

  # Enable all log types for audit trail
  enabled_cluster_log_types = [
    "api",
    "audit",
    "authenticator",
    "controllerManager",
    "scheduler",
  ]
}

# KMS key for envelope encryption
resource "aws_kms_key" "eks" {
  description             = "EKS secret encryption key"
  deletion_window_in_days = 7
  enable_key_rotation     = true
}
```

**Why envelope encryption matters**: By default, Kubernetes secrets are stored in etcd as base64-encoded plain text. Anyone with access to the etcd backup can read every secret. Envelope encryption wraps each secret with a KMS key, so the etcd data is encrypted at rest.

### Layer 3: Network Security

```hcl
# Restrict inter-pod communication with Network Policies
# (Requires a CNI that supports Network Policies, like Calico)

resource "kubernetes_network_policy" "default_deny" {
  metadata {
    name      = "default-deny-all"
    namespace = "production"
  }

  spec {
    pod_selector {}

    policy_types = ["Ingress", "Egress"]

    # No ingress or egress rules = deny everything
    # Pods in this namespace cannot talk to anything unless
    # another NetworkPolicy explicitly allows it
  }
}

resource "kubernetes_network_policy" "allow_api_to_db" {
  metadata {
    name      = "allow-api-to-db"
    namespace = "production"
  }

  spec {
    pod_selector {
      match_labels = {
        app = "database"
      }
    }

    policy_types = ["Ingress"]

    ingress {
      from {
        pod_selector {
          match_labels = {
            app = "api-server"
          }
        }
      }
      ports {
        port     = 5432
        protocol = "TCP"
      }
    }
  }
}
```

### Layer 5: Pod Security

Kubernetes Pod Security Standards define three levels: Privileged, Baseline, and Restricted.

```hcl
# Enforce restricted pod security standard at the namespace level
resource "kubernetes_namespace" "production" {
  metadata {
    name = "production"

    labels = {
      "pod-security.kubernetes.io/enforce" = "restricted"
      "pod-security.kubernetes.io/audit"   = "restricted"
      "pod-security.kubernetes.io/warn"    = "restricted"
    }
  }
}
```

The "restricted" level prevents:
- Running as root
- Privilege escalation
- Host network/PID/IPC namespaces
- Non-read-only root filesystems (with some exceptions)
- Capabilities beyond a minimal set

> **What breaks in production**: You enable the "restricted" Pod Security Standard on a namespace, and half your pods fail to start. Many Helm charts and third-party images run as root by default. You must audit all your workloads before enforcing restricted mode. Start with "warn" mode to see what would break, then "audit" to log violations, and finally "enforce" to block them.

---

## 3. Secrets Management

Never store secrets in Terraform state, Kubernetes ConfigMaps, or environment variables in your Helm values. Here is the right way.

### The Secrets Hierarchy

```
LEAST SECURE                                      MOST SECURE
     |                                                   |
     |  Plain text   K8s Secrets  Sealed      External   |
     |  in code      (base64)    Secrets      Secrets    |
     |                                        Operator   |
     |  Never do     Default but  Better      Best       |
     |  this         not great                           |
```

### Pattern 1: External Secrets Operator (Recommended)

The External Secrets Operator syncs secrets from AWS Secrets Manager (or SSM Parameter Store, Vault, etc.) into Kubernetes Secrets. The flow:

```
┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│  AWS Secrets │     │  External    │     │  Kubernetes  │
│  Manager     │<────│  Secrets     │────>│  Secret      │
│              │     │  Operator    │     │  (auto-      │
│  Source of   │     │  (in-cluster)│     │   synced)    │
│  truth       │     │              │     │              │
└──────────────┘     └──────────────┘     └──────────────┘
```

**Step 1: Create the secret in AWS Secrets Manager (via Terraform)**

```hcl
resource "aws_secretsmanager_secret" "db_password" {
  name        = "${var.cluster_name}/database/password"
  description = "Production database password"

  # Replicate to another region for DR
  replica {
    region = "us-west-2"
  }
}

resource "aws_secretsmanager_secret_version" "db_password" {
  secret_id = aws_secretsmanager_secret.db_password.id

  # The actual secret value -- set this manually or via CI/CD
  # Do NOT hardcode the password here
  secret_string = jsonencode({
    username = "admin"
    password = var.db_password  # Passed via environment variable, never in code
  })

  lifecycle {
    ignore_changes = [secret_string]  # Don't overwrite after initial creation
  }
}
```

**Step 2: Deploy External Secrets Operator (via Terraform)**

See the recipe in doc 05 (Helm + Kubernetes section).

**Step 3: Create a SecretStore and ExternalSecret (via Kubernetes manifests)**

```yaml
# This can be managed by Terraform or ArgoCD
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: aws-secrets-manager
spec:
  provider:
    aws:
      service: SecretsManager
      region: us-east-1
      auth:
        jwt:
          serviceAccountRef:
            name: external-secrets
            namespace: external-secrets
---
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: db-credentials
  namespace: production
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: aws-secrets-manager
    kind: ClusterSecretStore
  target:
    name: db-credentials
    creationPolicy: Owner
  data:
    - secretKey: username
      remoteRef:
        key: my-cluster/database/password
        property: username
    - secretKey: password
      remoteRef:
        key: my-cluster/database/password
        property: password
```

### Pattern 2: SOPS + Age for Git-Stored Secrets

For teams that want secrets in Git (encrypted), Mozilla SOPS with age encryption works well:

```bash
# Encrypt a values file
sops --encrypt --age <public-key> secrets.yaml > secrets.enc.yaml

# In CI/CD, decrypt before Terraform apply
sops --decrypt secrets.enc.yaml > secrets.yaml
```

This keeps secrets in version control (auditable) but encrypted (safe).

> **What breaks in production**: You rotate a database password in AWS Secrets Manager, but the External Secrets Operator's refresh interval is set to 24 hours. Your application uses the old password for up to 24 hours. If the old password is revoked immediately, your app goes down. Set the refresh interval based on your rotation policy. For critical secrets, use 5-15 minutes.

---

## 4. Karpenter vs Cluster Autoscaler

Both tools add and remove nodes automatically. But they take fundamentally different approaches.

### Cluster Autoscaler (The Old Way)

```
┌─────────────────────────────────────────────────────┐
│              CLUSTER AUTOSCALER                      │
│                                                      │
│  You define:                                         │
│    Node Group A: t3.medium, min=2, max=10            │
│    Node Group B: m5.xlarge, min=1, max=5             │
│    Node Group C: p3.2xlarge (GPU), min=0, max=3      │
│                                                      │
│  CA watches for unschedulable pods                   │
│     -> Finds a node group that fits                  │
│     -> Increases the ASG desired count               │
│     -> AWS launches the EC2 instance                 │
│     -> Pod gets scheduled (2-5 min total)            │
│                                                      │
│  Problems:                                           │
│    - You must pre-define every node group             │
│    - Cannot mix instance types well                   │
│    - Scaling is slow (ASG -> EC2 -> kubelet)          │
│    - Under-utilization when workloads vary            │
└─────────────────────────────────────────────────────┘
```

```hcl
# Cluster Autoscaler with Terraform
resource "helm_release" "cluster_autoscaler" {
  name       = "cluster-autoscaler"
  repository = "https://kubernetes.github.io/autoscaler"
  chart      = "cluster-autoscaler"
  version    = "9.29.3"
  namespace  = "kube-system"

  values = [
    yamlencode({
      autoDiscovery = {
        clusterName = module.eks.cluster_name
      }
      awsRegion = var.region

      extraArgs = {
        "balance-similar-node-groups"    = true
        "skip-nodes-with-local-storage"  = false
        "scale-down-utilization-threshold" = 0.5
        "scale-down-delay-after-add"     = "5m"
      }
    })
  ]
}
```

### Karpenter (The New Way)

```
┌─────────────────────────────────────────────────────┐
│              KARPENTER                                │
│                                                      │
│  You define:                                         │
│    NodePool: "I need Linux AMD64 nodes,              │
│              any instance type from c5, m5, r5       │
│              families, spot preferred,               │
│              size between xlarge and 4xlarge"         │
│                                                      │
│  Karpenter watches for unschedulable pods            │
│     -> Calculates exact resources needed             │
│     -> Picks the cheapest instance type that fits    │
│     -> Launches the EC2 instance directly (no ASG)   │
│     -> Pod gets scheduled (30-90 sec total)          │
│                                                      │
│  Advantages:                                         │
│    - No pre-defined node groups                      │
│    - Bin-packs efficiently (right-sizes nodes)       │
│    - Much faster scaling (no ASG layer)              │
│    - Intelligent spot instance selection             │
│    - Automatic node consolidation                    │
└─────────────────────────────────────────────────────┘
```

```hcl
# Karpenter with Terraform
module "karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "20.0.0"

  cluster_name = module.eks.cluster_name

  # Create the IAM role and instance profile
  irsa_oidc_provider_arn = module.eks.oidc_provider_arn

  # Create the SQS queue for spot interruption handling
  enable_spot_termination = true
}

resource "helm_release" "karpenter" {
  depends_on = [module.karpenter]

  name       = "karpenter"
  namespace  = "karpenter"
  repository = "oci://public.ecr.aws/karpenter"
  chart      = "karpenter"
  version    = "0.33.0"

  create_namespace = true

  values = [
    yamlencode({
      settings = {
        clusterName       = module.eks.cluster_name
        clusterEndpoint   = module.eks.cluster_endpoint
        interruptionQueue = module.karpenter.queue_name
      }
      serviceAccount = {
        annotations = {
          "eks.amazonaws.com/role-arn" = module.karpenter.irsa_arn
        }
      }
    })
  ]
}

# Define a NodePool (what Karpenter uses to make scaling decisions)
resource "kubernetes_manifest" "karpenter_nodepool" {
  depends_on = [helm_release.karpenter]

  manifest = {
    apiVersion = "karpenter.sh/v1beta1"
    kind       = "NodePool"
    metadata = {
      name = "default"
    }
    spec = {
      template = {
        spec = {
          requirements = [
            {
              key      = "kubernetes.io/arch"
              operator = "In"
              values   = ["amd64"]
            },
            {
              key      = "karpenter.sh/capacity-type"
              operator = "In"
              values   = ["spot", "on-demand"]
            },
            {
              key      = "karpenter.k8s.aws/instance-category"
              operator = "In"
              values   = ["c", "m", "r"]
            },
            {
              key      = "karpenter.k8s.aws/instance-size"
              operator = "In"
              values   = ["large", "xlarge", "2xlarge"]
            },
          ]
          nodeClassRef = {
            apiVersion = "karpenter.k8s.aws/v1beta1"
            kind       = "EC2NodeClass"
            name       = "default"
          }
        }
      }
      limits = {
        cpu    = "100"     # Max 100 vCPUs across all nodes
        memory = "400Gi"
      }
      disruption = {
        consolidationPolicy = "WhenUnderutilized"
        expireAfter         = "720h"  # Replace nodes after 30 days
      }
    }
  }
}
```

### When to Use Which

| Criteria | Cluster Autoscaler | Karpenter |
|---|---|---|
| Scaling speed | 2-5 minutes | 30-90 seconds |
| Instance flexibility | Limited to node group types | Chooses from many types |
| Spot handling | Basic | Advanced (consolidation, interruption handling) |
| Complexity | Low | Medium |
| Maturity | Very mature | Mature (GA since 2023) |
| AWS-specific | No (works on GKE, AKS) | Yes (AWS only) |

**Recommendation**: For new EKS clusters, use Karpenter. For existing clusters with stable node groups, Cluster Autoscaler is fine.

> **What breaks in production**: You deploy Karpenter but forget to set `limits` on the NodePool. A bug in your application creates 10,000 pods. Karpenter dutifully launches hundreds of EC2 instances. Your AWS bill spikes by $50,000 before anyone notices. Always set CPU and memory limits on NodePools. Also set up billing alerts.

---

## 5. Spot Instances Strategy

Spot instances cost 60-90% less than on-demand but can be reclaimed by AWS with 2 minutes notice. Using them well requires strategy.

### The Diversification Principle

AWS reclaims spot instances from the lowest-demand pools first. If everyone is using m5.xlarge spot instances, that pool drains first. Diversify across instance types, sizes, and availability zones.

```hcl
# Karpenter NodePool with spot diversification
spec = {
  template = {
    spec = {
      requirements = [
        {
          key      = "karpenter.sh/capacity-type"
          operator = "In"
          values   = ["spot", "on-demand"]  # Prefer spot, fall back to on-demand
        },
        {
          key      = "karpenter.k8s.aws/instance-category"
          operator = "In"
          values   = ["c", "m", "r"]  # Compute, General, Memory optimized
        },
        {
          key      = "karpenter.k8s.aws/instance-generation"
          operator = "Gte"
          values   = ["5"]  # 5th gen or newer
        },
        {
          key      = "karpenter.k8s.aws/instance-size"
          operator = "In"
          values   = ["large", "xlarge", "2xlarge", "4xlarge"]
        },
      ]
    }
  }
}
```

This gives Karpenter dozens of instance types to choose from, making it unlikely that all pools are drained at once.

### The On-Demand Baseline

Never run critical workloads on 100% spot. Use a mix:

```
┌────────────────────────────────────────────┐
│            WORKLOAD ALLOCATION              │
│                                             │
│  ┌──────────────────────────────────────┐  │
│  │ CRITICAL (on-demand)                  │  │
│  │  - API servers (minimum 2 replicas)   │  │
│  │  - Database proxies                   │  │
│  │  - Monitoring/alerting                │  │
│  │                                        │  │
│  │  ~20-30% of total compute             │  │
│  └──────────────────────────────────────┘  │
│                                             │
│  ┌──────────────────────────────────────┐  │
│  │ FLEXIBLE (spot)                       │  │
│  │  - Workers, batch jobs                │  │
│  │  - Additional API replicas            │  │
│  │  - CI/CD runners                      │  │
│  │  - Dev/staging environments           │  │
│  │                                        │  │
│  │  ~70-80% of total compute             │  │
│  └──────────────────────────────────────┘  │
└────────────────────────────────────────────┘
```

### Handling Spot Interruptions

When AWS reclaims a spot instance, Karpenter receives the 2-minute warning via an SQS queue and:

1. Cordons the node (prevents new pods from scheduling)
2. Drains the node (evicts existing pods gracefully)
3. Pods are rescheduled on other nodes

Your application must handle graceful shutdown within the 2-minute window. This means:

```yaml
# In your Deployment spec
spec:
  terminationGracePeriodSeconds: 90  # Give pods 90s to shutdown
  containers:
    - name: app
      lifecycle:
        preStop:
          exec:
            command: ["/bin/sh", "-c", "sleep 5"]  # Allow time for deregistration
```

And in your application code: handle SIGTERM, finish in-flight requests, close database connections, flush buffers.

---

## 6. Cost Optimization

EKS costs add up fast. Here is where the money goes and how to reduce it.

### The Cost Breakdown

```
┌─────────────────────────────────────────────────────┐
│             TYPICAL EKS MONTHLY COSTS                │
│                                                      │
│  EKS Control Plane:     $73/month (fixed)            │
│  EC2 Instances:         $2,000-50,000+ (variable)    │
│  NAT Gateways:          $35/month per AZ             │
│  Load Balancers:        $18/month + data transfer    │
│  EBS Volumes:           Variable (PVCs)              │
│  Data Transfer:         $0.01-0.09/GB (sneaky)       │
│  CloudWatch Logs:       Variable (can be huge)       │
│                                                      │
│  EC2 instances are 70-85% of total cost              │
└─────────────────────────────────────────────────────┘
```

### Optimization 1: Right-Size Your Pods

Most pods request far more CPU and memory than they use. This wastes money because Kubernetes reserves resources based on requests, not actual usage.

```bash
# Find pods that request much more than they use
# (Install metrics-server first)
kubectl top pods -n production
```

Use the Vertical Pod Autoscaler (VPA) in recommendation mode to get right-sizing suggestions:

```hcl
resource "helm_release" "vpa" {
  name       = "vpa"
  repository = "https://charts.fairwinds.com/stable"
  chart      = "vpa"
  namespace  = "kube-system"

  values = [
    yamlencode({
      recommender = { enabled = true }
      updater     = { enabled = false }  # Recommendation mode only
      admissionController = { enabled = false }
    })
  ]
}
```

### Optimization 2: Use Spot Instances (See Section 5)

Typical savings: 60-80% on compute costs.

### Optimization 3: Single NAT Gateway for Non-Production

```hcl
module "vpc" {
  source = "../../modules/vpc"

  # Production: one NAT gateway per AZ ($105/month for 3 AZs)
  # Dev/staging: single NAT gateway ($35/month)
  single_nat_gateway = var.environment != "production"
}
```

### Optimization 4: Reduce Data Transfer Costs

Data transfer between AZs costs $0.01/GB. This adds up for high-traffic services.

```yaml
# Use topology-aware routing to prefer same-AZ communication
apiVersion: v1
kind: Service
metadata:
  annotations:
    service.kubernetes.io/topology-mode: Auto
```

### Optimization 5: Log Filtering

CloudWatch Logs for EKS control plane can cost hundreds of dollars per month. Only enable the log types you actually use:

```hcl
# Instead of enabling everything:
enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

# Be selective:
enabled_cluster_log_types = ["audit"]  # Most important for security
```

### Optimization 6: Savings Plans and Reserved Instances

For your on-demand baseline (the compute that runs 24/7), purchase Compute Savings Plans. They provide 30-60% savings with a 1-year or 3-year commitment.

```
┌──────────────────────────────────────────────┐
│         COST OPTIMIZATION STACK               │
│                                               │
│  1. Right-size pods (free, immediate)         │
│  2. Spot instances for flexible workloads     │
│  3. Karpenter consolidation (packs nodes)     │
│  4. Single NAT GW for non-prod               │
│  5. Topology-aware routing                    │
│  6. Log filtering                             │
│  7. Savings Plans for on-demand baseline      │
│                                               │
│  Combined savings: 50-75% vs naive setup      │
└──────────────────────────────────────────────┘
```

> **What breaks in production**: You aggressively right-size pods to save money. Your API server requests 200m CPU and 256Mi memory. Under normal load, it uses 150m CPU and 200Mi memory. During Black Friday, traffic spikes 10x. The HPA tries to scale up, but each new pod requests 200m CPU, and the nodes are already packed tight (because Karpenter consolidated them). New pods are Pending for 2 minutes while Karpenter launches new nodes. During those 2 minutes, existing pods are overwhelmed and start returning 503 errors. Always leave headroom in your resource requests and set appropriate HPA thresholds.

---

## 7. Reliability Patterns

### Pattern 1: Pod Disruption Budgets (PDBs)

PDBs prevent too many pods from being taken down simultaneously during voluntary disruptions (node drains, upgrades, Karpenter consolidation).

```hcl
resource "kubernetes_pod_disruption_budget_v1" "api" {
  metadata {
    name      = "api-server-pdb"
    namespace = "production"
  }

  spec {
    min_available = "50%"  # At least half the pods must be running

    selector {
      match_labels = {
        app = "api-server"
      }
    }
  }
}
```

Without PDBs, Karpenter might drain a node running 3 of your 4 API server replicas, leaving only 1 to handle all traffic.

### Pattern 2: Topology Spread Constraints

Spread pods across availability zones and nodes:

```yaml
spec:
  topologySpreadConstraints:
    - maxSkew: 1
      topologyKey: topology.kubernetes.io/zone
      whenUnsatisfiable: DoNotSchedule
      labelSelector:
        matchLabels:
          app: api-server
    - maxSkew: 1
      topologyKey: kubernetes.io/hostname
      whenUnsatisfiable: ScheduleAnyway
      labelSelector:
        matchLabels:
          app: api-server
```

This ensures your api-server pods are evenly spread across AZs (hard requirement) and across nodes (soft preference).

### Pattern 3: Health Checks

Kubernetes has three types of probes. Use all three:

```yaml
spec:
  containers:
    - name: app
      livenessProbe:        # "Is the process stuck?" - restarts the container
        httpGet:
          path: /healthz
          port: 8080
        initialDelaySeconds: 15
        periodSeconds: 10

      readinessProbe:       # "Can it handle traffic?" - removes from service
        httpGet:
          path: /ready
          port: 8080
        initialDelaySeconds: 5
        periodSeconds: 5

      startupProbe:         # "Has it finished starting?" - protects slow starters
        httpGet:
          path: /healthz
          port: 8080
        failureThreshold: 30
        periodSeconds: 10
```

### Pattern 4: Horizontal Pod Autoscaler (HPA)

```hcl
resource "kubernetes_horizontal_pod_autoscaler_v2" "api" {
  metadata {
    name      = "api-server"
    namespace = "production"
  }

  spec {
    scale_target_ref {
      api_version = "apps/v1"
      kind        = "Deployment"
      name        = "api-server"
    }

    min_replicas = 3
    max_replicas = 50

    metric {
      type = "Resource"
      resource {
        name = "cpu"
        target {
          type                = "Utilization"
          average_utilization = 60  # Scale up when avg CPU > 60%
        }
      }
    }

    behavior {
      scale_up {
        stabilization_window_seconds = 30    # React quickly
        select_policy                = "Max"
        policy {
          type           = "Percent"
          value          = 100      # Double the pods
          period_seconds = 60
        }
      }
      scale_down {
        stabilization_window_seconds = 300   # Wait 5 min before scaling down
        select_policy                = "Min"
        policy {
          type           = "Percent"
          value          = 10       # Remove 10% of pods at a time
          period_seconds = 60
        }
      }
    }
  }
}
```

**Key insight**: Scale up fast, scale down slow. You never want to be caught under-provisioned, but scaling down too aggressively causes thrashing.

### Pattern 5: Multi-AZ Node Distribution

```hcl
# For managed node groups
resource "aws_eks_node_group" "main" {
  cluster_name    = module.eks.cluster_name
  node_group_name = "main"
  subnet_ids      = module.vpc.private_subnet_ids  # Subnets in multiple AZs

  scaling_config {
    desired_size = 6
    min_size     = 3
    max_size     = 20
  }
}
```

AWS distributes nodes across the provided subnets (and thus AZs) automatically. Combined with topology spread constraints, this ensures your workload survives an entire AZ going down.

> **What breaks in production**: You have 3 replicas of your API server, each in a different AZ. AZ-a goes down. The replica in AZ-a is lost. HPA tries to scale up to maintain 3 replicas, but the new pod lands in AZ-b (already has a replica). Now AZ-b has 2 replicas and AZ-c has 1. If AZ-b goes down next, you lose 2 of 3 replicas. Topology spread constraints prevent this -- they ensure the new pod goes to AZ-c.

---

## 8. Multi-Account Strategy

Running everything in a single AWS account is a security and operational risk. Here is how to structure multiple accounts.

### The Account Layout

```
┌─────────────────────────────────────────────────────────────┐
│                   AWS ORGANIZATION                           │
│                                                              │
│  ┌──────────────┐  Root account (billing only, no workloads) │
│  │  Management  │  Has OrganizationAccountAccessRole         │
│  │  Account     │                                            │
│  └──────┬───────┘                                            │
│         │                                                    │
│    ┌────┴────────────────────────────────┐                   │
│    │                                     │                   │
│    v                                     v                   │
│  ┌──────────────┐              ┌──────────────┐             │
│  │  Security     │              │  Shared       │             │
│  │  Account      │              │  Services     │             │
│  │               │              │  Account      │             │
│  │  - CloudTrail │              │               │             │
│  │  - GuardDuty  │              │  - ECR repos  │             │
│  │  - Config     │              │  - Terraform  │             │
│  │  - Audit logs │              │    state      │             │
│  └──────────────┘              │  - CI/CD      │             │
│                                 └──────────────┘             │
│                                                              │
│    ┌────────────────┬────────────────┐                       │
│    v                v                v                       │
│  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐        │
│  │  Dev          │ │  Staging     │ │  Production  │        │
│  │  Account      │ │  Account     │ │  Account     │        │
│  │               │ │              │ │              │        │
│  │  - EKS dev    │ │  - EKS stg   │ │  - EKS prod  │        │
│  │  - Relaxed    │ │  - Prod-like │ │  - Strict    │        │
│  │    policies   │ │    config    │ │    policies  │        │
│  └──────────────┘ └──────────────┘ └──────────────┘        │
└─────────────────────────────────────────────────────────────┘
```

### Cross-Account Access for Terraform

```hcl
# In the shared services account: role that Terraform assumes
resource "aws_iam_role" "terraform_production" {
  name = "TerraformProductionAccess"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${var.shared_services_account_id}:role/CICDRunner"
        }
        Action = "sts:AssumeRole"
        Condition = {
          StringEquals = {
            "sts:ExternalId" = var.external_id
          }
        }
      }
    ]
  })
}

# In Terraform: assume the role
provider "aws" {
  alias  = "production"
  region = "us-east-1"

  assume_role {
    role_arn    = "arn:aws:iam::${var.production_account_id}:role/TerraformProductionAccess"
    external_id = var.external_id
  }
}
```

### Cross-Account ECR Access

Your production EKS cluster needs to pull images from the shared services ECR:

```hcl
# In the shared services account: ECR repository policy
resource "aws_ecr_repository_policy" "cross_account" {
  repository = aws_ecr_repository.app.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowProductionPull"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${var.production_account_id}:root"
        }
        Action = [
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability",
        ]
      }
    ]
  })
}
```

### Service Control Policies (SCPs)

SCPs are guardrails applied at the organizational level. They restrict what any IAM principal in the account can do, regardless of their IAM policies.

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "DenyDisablingCloudTrail",
      "Effect": "Deny",
      "Action": [
        "cloudtrail:StopLogging",
        "cloudtrail:DeleteTrail"
      ],
      "Resource": "*"
    },
    {
      "Sid": "DenyLeavingOrganization",
      "Effect": "Deny",
      "Action": "organizations:LeaveOrganization",
      "Resource": "*"
    },
    {
      "Sid": "RestrictRegions",
      "Effect": "Deny",
      "NotAction": [
        "iam:*",
        "sts:*",
        "s3:*",
        "cloudfront:*"
      ],
      "Resource": "*",
      "Condition": {
        "StringNotEquals": {
          "aws:RequestedRegion": ["us-east-1", "us-west-2"]
        }
      }
    }
  ]
}
```

> **What breaks in production**: You set up a multi-account strategy but use the same Terraform state bucket for all accounts. An engineer working on dev misconfigures their backend and starts writing to the production state file. The next production apply uses the corrupted state. Each account should have its own state bucket in its own account.

---

## 9. Putting It All Together

Here is what a production-grade EKS security and scaling configuration looks like when all the pieces are assembled:

```hcl
# main.tf - Production environment

# 1. Networking with security
module "vpc" {
  source = "../../modules/vpc"

  vpc_cidr           = "10.1.0.0/16"
  environment        = "production"
  single_nat_gateway = false  # HA: one per AZ
}

# 2. EKS with security hardening
module "eks" {
  source = "../../modules/eks"

  cluster_name    = "prod-main"
  cluster_version = "1.28"
  vpc_id          = module.vpc.vpc_id
  subnet_ids      = module.vpc.private_subnet_ids

  # Security
  cluster_endpoint_private_access = true
  cluster_endpoint_public_access  = false
  cluster_encryption_key_arn      = module.kms.key_arn
  enable_audit_logs               = true
}

# 3. Karpenter for auto-scaling
module "karpenter" {
  source = "../../modules/karpenter"

  cluster_name = module.eks.cluster_name
  # ...
}

# 4. Security add-ons
resource "helm_release" "falco" { ... }           # Runtime security
resource "helm_release" "cert_manager" { ... }     # TLS certificates
resource "helm_release" "external_secrets" { ... }  # Secrets management

# 5. Networking add-ons
resource "helm_release" "aws_lb_controller" { ... }
resource "helm_release" "external_dns" { ... }

# 6. Observability
resource "helm_release" "kube_prometheus_stack" { ... }

# 7. PDBs for critical workloads
resource "kubernetes_pod_disruption_budget_v1" "api" { ... }
```

The order matters. The dependency chain is:

```
VPC -> EKS -> Node Groups -> Karpenter -> Platform Add-ons -> Applications
```

Each layer builds on the previous one. Skip a layer, and the layers above it will fail in confusing ways.

---

## 10. Test Yourself

**Question 1**: Your EKS pods need to read from an S3 bucket. The node group IAM role has `AmazonS3FullAccess`. A security auditor flags this. What is the correct approach?

**Answer**: Remove `AmazonS3FullAccess` from the node group role. Create an IRSA role with a policy that grants only `s3:GetObject` on the specific bucket and prefix. Annotate the Kubernetes ServiceAccount with the IRSA role ARN. Only the pods using that ServiceAccount will have S3 access, and only for reading from the specific bucket.

**Question 2**: You enable envelope encryption on your EKS cluster. Someone deletes the KMS key. What happens?

**Answer**: All Kubernetes secrets become unreadable. The EKS cluster cannot decrypt secrets stored in etcd. Any pod that mounts a secret will fail. Any new secret creation will fail. This is catastrophic. Always set `deletion_window_in_days` to at least 7 days on the KMS key, enable key rotation, and restrict who can delete KMS keys via IAM policies.

**Question 3**: You have Karpenter managing nodes with no limits on the NodePool. A CI/CD pipeline bug creates 5,000 pods. What happens, and how do you prevent it?

**Answer**: Karpenter launches hundreds of EC2 instances to accommodate the pods. Your AWS bill could reach thousands of dollars per hour. Prevention: (1) Set `limits` on the NodePool (e.g., `cpu: "100"`, `memory: "400Gi"`). (2) Set `ResourceQuota` on Kubernetes namespaces. (3) Set up AWS billing alerts. (4) Use LimitRange to set default resource requests, preventing pods from being created without limits.

**Question 4**: Your application uses the External Secrets Operator to sync secrets from AWS Secrets Manager. You rotate the database password in Secrets Manager. The application continues to use the old password. Why?

**Answer**: The ExternalSecret resource has a `refreshInterval` that determines how often it checks for updates. If set to `1h`, the new password will not be synced for up to 1 hour. Additionally, the application might cache the password in memory and not re-read the Kubernetes Secret. Fix: (1) Set a shorter refresh interval. (2) Ensure your application watches for Secret changes or periodically re-reads credentials. (3) Consider using Reloader to automatically restart pods when secrets change.

**Question 5**: You are running a critical API on spot instances. AWS sends a 2-minute termination notice. Your API server takes 3 minutes to drain all connections. What happens?

**Answer**: After 2 minutes, AWS forcibly terminates the instance regardless of whether the pod has finished draining. In-flight requests are dropped. Fix: (1) Set `terminationGracePeriodSeconds` to less than 120 seconds. (2) Implement graceful shutdown in your application that completes quickly. (3) Use connection draining on the load balancer. (4) Run critical workloads on on-demand instances and use spot only for additional capacity.

**Question 6**: You have a PDB set to `minAvailable: 2` on a deployment with 3 replicas. Karpenter tries to consolidate nodes and drain a node running 1 of the 3 replicas. What happens?

**Answer**: Karpenter checks the PDB before draining. Since draining 1 replica would leave 2 running (which satisfies `minAvailable: 2`), Karpenter proceeds with the drain. The pod is evicted, rescheduled on another node, and traffic continues flowing through the remaining 2 replicas. If all 3 replicas were on the node being drained, Karpenter would only be allowed to evict 1 at a time, waiting for the replacement to be ready before evicting the next.

**Question 7**: Your EKS cluster has public endpoint access enabled. An attacker scans the internet and finds your cluster's API server. What stops them from accessing it?

**Answer**: Multiple layers: (1) `public_access_cidrs` should restrict which IPs can reach the endpoint. (2) Authentication is required (aws-iam-authenticator verifies that the caller has valid AWS credentials). (3) RBAC restricts what authenticated users can do. (4) For maximum security, disable the public endpoint entirely and use a VPN or bastion host to access the cluster. The default is secure enough for most cases if CIDR restrictions are in place.

**Question 8**: You set up HPA with target CPU utilization of 80%. Under load, pods are at 85% CPU but HPA is not scaling up. What could be wrong?

**Answer**: Common causes: (1) metrics-server is not installed or not working. (2) The deployment does not have CPU resource requests set (HPA needs requests to calculate utilization percentage). (3) The HPA has already reached `maxReplicas`. (4) The stabilization window prevents scale-up (check `behavior.scaleUp.stabilizationWindowSeconds`). Debug with: `kubectl describe hpa <name>` to see the current metrics and conditions.

**Question 9**: Your production account has an SCP that denies all actions outside us-east-1 and us-west-2. You try to create an EKS cluster in eu-west-1 for European users. The Terraform apply fails. How do you solve this without removing the SCP?

**Answer**: Create a separate Organizational Unit (OU) for accounts that need European regions. Apply a less restrictive SCP to that OU. Move or create a new AWS account in that OU for the European deployment. SCPs are inherited from the OU hierarchy, so you can have different policies for different groups of accounts.

**Question 10**: You have cost-optimized your EKS cluster and reduced your monthly bill from $15,000 to $6,000. Six months later, costs have crept back up to $12,000. What likely happened?

**Answer**: Common causes of cost creep: (1) New services were deployed without resource requests, so pods got default large allocations. (2) Spot instance savings decreased because the team started using on-demand for everything "just to be safe." (3) Nobody is monitoring the VPA recommendations, so pods are still over-provisioned. (4) Log volumes increased (more services, more verbose logging). (5) Data transfer costs increased with more cross-AZ traffic. Fix: Set up regular cost reviews, enforce resource quotas per namespace, require resource requests on all pods, and use a tool like Kubecost for continuous cost visibility.

---

> **Key Takeaway**: Security, scaling, and cost optimization are not one-time configurations. They are ongoing practices. Set up the foundations (IRSA, Karpenter, PDBs, monitoring), but also set up the processes (regular security audits, cost reviews, capacity planning). The infrastructure you build today will be inherited by the team that joins tomorrow -- make it secure and efficient by default, not by heroic effort.
