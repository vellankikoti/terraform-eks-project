# Terraform Like a 10-Year AWS DevOps Veteran

> **Master Terraform from zero to production-grade AWS EKS deployment**
> Written by someone who's broken production at 3 AM and knows exactly why things fail.

---

## What This Is

This is **not another Terraform tutorial**. This is a **complete mental model** of how world-class DevOps teams build, secure, and scale infrastructure on AWS.

After completing this material, you'll think like someone with **10+ years of battle-tested experience**.

### What You'll Gain

- Deep understanding of Terraform internals (not just syntax)
- Production-grade EKS setup with all critical add-ons
- Real failure scenarios and how to debug them
- Interview confidence from junior to staff engineer level
- Visual mental models that make complex concepts intuitive
- Copy-paste-ready code used in companies serving millions of users

---

## Learning Path

### Phase 1: Foundation (Week 1-2)

**Start here if you're new to Terraform or need to solidify fundamentals.**

1. **[Terraform Fundamentals](docs/01-fundamentals.md)** -- START HERE
   - What Terraform *really* is (not marketing BS)
   - Declarative vs Imperative (explained like you're 10)
   - State files (the "bank ledger" of infrastructure)
   - Providers, Resources, Data Sources
   - The Terraform workflow (`init -> plan -> apply -> destroy`)

2. **[Terraform Internals](docs/02-internals.md)** -- CRITICAL DEPTH
   - Dependency graph construction
   - How `terraform plan` actually works under the hood
   - State locking (S3 + DynamoDB)
   - Drift detection and reconciliation
   - Why `count` vs `for_each` matters in production

### Phase 2: Production Patterns (Week 3-4)

3. **[Project Structure](docs/03-project-structure.md)**
   - Battle-tested repository layouts
   - Module design patterns
   - Multi-environment strategies
   - Monorepo vs multi-repo

4. **[AWS EKS Production Setup](docs/04-eks-production.md)** -- FLAGSHIP CONTENT
   - Complete VPC design (multi-AZ, private subnets)
   - EKS cluster (secure, production-grade)
   - IAM best practices & IRSA
   - All critical Kubernetes add-ons (with real Terraform code)

5. **[Terraform + Helm + Kubernetes](docs/05-helm-kubernetes.md)**
   - When to use what
   - Dependency ordering
   - Common mistakes and fixes

### Phase 3: Expert Level (Week 5-6)

6. **[Security, Scaling & Reliability](docs/06-security-scaling.md)**
   - Least privilege IAM
   - Secrets management
   - Multi-account strategies
   - Cost optimization
   - Karpenter vs Cluster Autoscaler
   - Spot instance strategies

7. **[Testing & Validation](docs/07-testing.md)**
   - Terratest patterns
   - CI/CD pipelines
   - Safe production rollouts
   - Security scanning (tfsec, checkov, OPA)

8. **[Debugging & War Stories](docs/08-debugging-war-stories.md)** -- LEARN FROM PAIN
   - Real production failures
   - State corruption recovery
   - EKS upgrade disasters
   - How experts think when things break

### Interview Preparation

9. **[Visual Explanations](docs/09-visual-explanations.md)**
   - ASCII diagrams for every major concept
   - Mental models and analogies
   - "Explain like I'm 5" versions

10. **[Interview Questions](docs/10-interview-questions.md)** -- INTERVIEW READY
    - Beginner to Staff Engineer level
    - Scenario-based deep dives
    - Trick questions interviewers use
    - Perfect answers with reasoning

---

## Terraform Code Structure

```
terraform/
├── bootstrap/                     # Remote state backend (run FIRST)
│   ├── main.tf                   # S3 bucket + DynamoDB table
│   ├── variables.tf
│   └── outputs.tf
├── modules/                       # Reusable, tested modules
│   ├── vpc/                      # Multi-AZ VPC with private subnets
│   ├── eks/                      # Production EKS cluster
│   ├── iam/                      # IAM roles, RBAC, aws-auth
│   └── addons/                   # Kubernetes add-ons
│       ├── aws-load-balancer-controller/   # ALB/NLB Ingress
│       ├── cluster-autoscaler/             # Node auto-scaling
│       ├── karpenter/                      # Next-gen autoscaler (spot-aware)
│       ├── ebs-csi-driver/                 # Block storage (EBS)
│       ├── efs-csi-driver/                 # Shared storage (EFS)
│       ├── external-dns/                   # Route53 DNS automation
│       ├── cert-manager/                   # TLS certificate automation
│       ├── argocd/                         # GitOps continuous delivery
│       ├── prometheus/                     # Metrics & alerting
│       ├── grafana/                        # Dashboards & visualization
│       ├── otel-collector/                 # Distributed tracing
│       ├── fluent-bit/                     # Log aggregation (CloudWatch/S3)
│       ├── external-secrets/               # AWS Secrets Manager integration
│       ├── vpa/                            # Vertical Pod Autoscaler
│       ├── splunk/                         # Enterprise log forwarding
│       ├── reloader/                       # ConfigMap/Secret reload
│       └── metrics-server/                 # HPA/VPA metrics
├── environments/                  # Environment-specific configs
│   ├── dev/                      # Cost-optimized (~$150-200/month)
│   ├── staging/                  # Prod-like, reduced scale (~$300-400/month)
│   └── prod/                     # Full HA, all features (~$500-800/month)
├── examples/                      # Standalone examples
│   ├── simple-app-deployment/    # Deploy Nginx with Ingress + HPA
│   ├── spot-instances/           # Cost-saving spot instance patterns
│   └── multi-team-rbac/          # Namespace isolation + RBAC
scripts/
├── setup.sh                       # Install all required tools
├── validate-all.sh                # Lint + validate all environments
└── cost-estimate.sh               # Infracost across all environments
.github/
└── workflows/
    └── terraform.yml              # CI/CD: lint -> security -> plan -> apply
```

### Environment Comparison

| Feature | Dev | Staging | Prod |
|---------|-----|---------|------|
| **VPC CIDR** | 10.10.0.0/16 | 10.20.0.0/16 | 10.0.0.0/16 |
| **AZs** | 2 | 2 | 3 |
| **System Nodes** | 2x t3.medium | 2x t3.large | 3x m5.large |
| **Spot Nodes** | Yes (t3 family) | Yes (t3/m5 family) | Yes (t3/m5/m6i) |
| **NAT Gateways** | 2 | 2 | 3 |
| **EKS Version** | 1.31 | 1.31 | 1.31 |
| **Monitoring** | Prometheus + Grafana | Full stack + OTel | Full stack + OTel |
| **GitOps** | - | - | ArgoCD |
| **DNS/TLS** | - | Cert-Manager | External DNS + Cert-Manager |
| **Log Retention** | 3 days | 14 days | 30 days |
| **Est. Monthly Cost** | $150-200 | $300-400 | $500-800 |

---

## Quick Start

### If You Have 5 Minutes

Read: **[Terraform Fundamentals](docs/01-fundamentals.md)** - Section 1 ("What Terraform Really Is")

You'll understand the core mental model that changes everything.

### If You Have 1 Hour

Read:
1. [Terraform Fundamentals](docs/01-fundamentals.md) (entire doc)
2. [Terraform Internals](docs/02-internals.md) - State Management section

You'll understand why Terraform is powerful and dangerous.

### If You Have 1 Day

Complete **Phase 1** of the learning path + review the [EKS Production Setup](docs/04-eks-production.md).

You'll be able to explain Terraform to your team with confidence.

### If You Have 1 Week

Complete **Phase 1 & 2**, deploy the example EKS cluster, break it, fix it.

You'll have hands-on production experience.

---

## Deploy Your First Cluster

```bash
# 1. Install tools
./scripts/setup.sh

# 2. Configure AWS
aws configure

# 3. Create remote state backend (one-time)
cd terraform/bootstrap
terraform init && terraform apply

# 4. Deploy dev environment
cd ../environments/dev
terraform init
terraform plan
terraform apply

# 5. Connect to cluster
$(terraform output -raw kubeconfig_command)
kubectl get nodes

# 6. IMPORTANT: Destroy when done (saves money!)
terraform destroy
```

See **[Getting Started Guide](GETTING_STARTED.md)** for detailed walkthrough.

---

## Who This Is For

**You'll love this if you are:**

- DevOps/Platform Engineer wanting to level up Terraform skills
- Backend Engineer responsible for infrastructure
- SRE managing Kubernetes on AWS
- Architect designing scalable systems
- Interview Candidate preparing for senior+ roles
- Self-taught Engineer wanting structured, deep knowledge

**Prerequisites:**

- Basic AWS concepts (EC2, VPC, IAM)
- Command-line comfort
- Basic understanding of YAML/JSON
- Git basics

---

## Learning Philosophy

### 1. Correctness First, Simplicity Second

We never sacrifice correctness for simplicity. Instead, we find **clearer ways to explain correct concepts**.

### 2. Learn from Failure

Every major concept includes:
- What it is
- Why it exists
- What breaks in production
- How to fix it

### 3. Visual Thinking

Complex systems are explained with ASCII diagrams, step-by-step flows, and real-world analogies.

### 4. Production Experience Embedded

Every code example is **battle-tested**. No "hello world" demos that break in production.

---

## Cost Warning

Running EKS and associated resources **costs money**:

| Resource | Monthly Cost |
|----------|-------------|
| EKS control plane | ~$75 |
| EC2 nodes (dev) | ~$60-100 |
| NAT Gateways | ~$35 each |
| Data transfer | Variable |

**Always destroy resources when done learning:**

```bash
terraform destroy
```

---

## Documentation Status

| Section | Status | Depth |
|---------|--------|-------|
| 01 - Fundamentals | Complete | Deep |
| 02 - Internals | Complete | Deep |
| 03 - Project Structure | Complete | Deep |
| 04 - EKS Production | Complete | Very Deep |
| 05 - Helm + Kubernetes | Complete | Deep |
| 06 - Security & Scaling | Complete | Very Deep |
| 07 - Testing | Complete | Deep |
| 08 - War Stories | Complete | Very Deep |
| 09 - Visual Explanations | Complete | High |
| 10 - Interview Questions | Complete | Very Deep |

---

## Let's Begin

Ready to think like a Terraform expert?

**Start here: [Terraform Fundamentals](docs/01-fundamentals.md)**

Or if you want to see production code first:

**Jump to: [AWS EKS Production Setup](docs/04-eks-production.md)**

---

**Made with real production scars by engineers who've been on-call at 3 AM**
