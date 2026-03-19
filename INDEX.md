# Complete Project Index

Quick reference to all files in this project.

## Start Here

| File | Purpose | Read Time |
|------|---------|-----------|
| `README.md` | Overview & learning path | 10 min |
| `GETTING_STARTED.md` | Step-by-step deployment | 15 min |
| `docs/01-fundamentals.md` | Terraform basics (start here for learning) | 1 hour |

## Documentation

### Learning Path (Read in Order)

| # | File | Topic | Depth | Time |
|---|------|-------|-------|------|
| 01 | `docs/01-fundamentals.md` | Terraform basics, mental models | Deep | 1 hour |
| 02 | `docs/02-internals.md` | How Terraform works under the hood | Deep | 1 hour |
| 03 | `docs/03-project-structure.md` | Repository layouts, module patterns | Deep | 45 min |
| 04 | `docs/04-eks-production.md` | EKS architecture & implementation | Very Deep | 1.5 hours |
| 05 | `docs/05-helm-kubernetes.md` | Terraform + Helm + K8s integration | Deep | 1 hour |
| 06 | `docs/06-security-scaling.md` | Security, scaling, cost optimization | Very Deep | 1.5 hours |
| 07 | `docs/07-testing.md` | Testing, CI/CD, safe rollouts | Deep | 1 hour |
| 08 | `docs/08-debugging-war-stories.md` | Real production failures & fixes | Very Deep | 1 hour |
| 09 | `docs/09-visual-explanations.md` | ASCII diagrams, mental models | High | 45 min |
| 10 | `docs/10-interview-questions.md` | Interview prep (junior to staff) | Very Deep | 2 hours |

**Total reading time: ~12 hours for complete mastery**

### Supporting Docs

| File | Purpose |
|------|---------|
| `PRD.md` | Product requirements and roadmap |
| `GETTING_STARTED.md` | Deploy your first cluster |
| `DIRECTORY_TREE.txt` | File structure reference |

## Terraform Code

### Bootstrap (Run First)

```
terraform/bootstrap/
├── main.tf          # S3 bucket + DynamoDB for remote state
├── variables.tf     # AWS region, project name, account ID
├── outputs.tf       # Bucket name, table name, backend config
└── README.md        # Step-by-step instructions
```

### Core Modules

| Module | Resources | Purpose |
|--------|-----------|---------|
| `modules/vpc/` | VPC, Subnets, NAT GW, VPC Endpoints | Network foundation |
| `modules/eks/` | EKS Cluster, Node Groups, IRSA, KMS | Kubernetes platform |
| `modules/iam/` | IAM Roles, aws-auth, RBAC mapping | Access control |

### Add-on Modules (18 total)

| Module | Category | Purpose |
|--------|----------|---------|
| `addons/aws-load-balancer-controller/` | Networking | ALB/NLB for Ingress |
| `addons/cluster-autoscaler/` | Scaling | Node auto-scaling |
| `addons/karpenter/` | Scaling | Next-gen autoscaler (spot-aware) |
| `addons/ebs-csi-driver/` | Storage | Block storage (EBS) |
| `addons/efs-csi-driver/` | Storage | Shared storage (EFS) |
| `addons/metrics-server/` | Scaling | HPA/VPA metrics |
| `addons/vpa/` | Scaling | Vertical Pod Autoscaler |
| `addons/external-dns/` | DNS | Route53 automation |
| `addons/cert-manager/` | TLS | Certificate automation |
| `addons/prometheus/` | Observability | Metrics & alerting |
| `addons/grafana/` | Observability | Dashboards |
| `addons/otel-collector/` | Observability | Distributed tracing |
| `addons/fluent-bit/` | Observability | Log aggregation |
| `addons/splunk/` | Observability | Enterprise log forwarding |
| `addons/external-secrets/` | Security | AWS Secrets Manager integration |
| `addons/argocd/` | GitOps | Continuous delivery |
| `addons/reloader/` | Operations | ConfigMap/Secret reload |

### Environments

| Environment | Nodes | Monthly Cost | Features |
|-------------|-------|-------------|----------|
| `environments/dev/` | 2 ON_DEMAND + spot | ~$150-200 | Core addons, Prometheus |
| `environments/staging/` | 2 ON_DEMAND + spot | ~$300-400 | Full stack, OTel, Cert-Manager |
| `environments/prod/` | 3 ON_DEMAND + spot | ~$500-800 | Everything, ArgoCD, Grafana, External DNS |

### Examples

| Example | Purpose |
|---------|---------|
| `examples/simple-app-deployment/` | Deploy Nginx with Ingress + HPA |
| `examples/spot-instances/` | Cost-saving spot instance patterns |
| `examples/multi-team-rbac/` | Namespace isolation + RBAC |

## CI/CD & Tooling

| File | Purpose |
|------|---------|
| `.github/workflows/terraform.yml` | CI/CD pipeline (lint -> security -> plan -> apply) |
| `.pre-commit-config.yaml` | Pre-commit hooks (fmt, validate, tfsec) |
| `Makefile` | Common operations (plan, apply, destroy) |
| `scripts/setup.sh` | Install all required tools |
| `scripts/validate-all.sh` | Lint and validate all environments |
| `scripts/cost-estimate.sh` | Cost estimation with Infracost |

## Quick Navigation

### I want to...

| Goal | Go To |
|------|-------|
| Learn Terraform from scratch | `docs/01-fundamentals.md` |
| Understand Terraform internals | `docs/02-internals.md` |
| Deploy my first cluster | `GETTING_STARTED.md` |
| Understand EKS architecture | `docs/04-eks-production.md` |
| Learn about security | `docs/06-security-scaling.md` |
| Prepare for interviews | `docs/10-interview-questions.md` |
| See visual diagrams | `docs/09-visual-explanations.md` |
| Add a new node group | `terraform/environments/dev/variables.tf` |
| Add a new addon | Copy pattern from `addons/cluster-autoscaler/` |
| Set up CI/CD | `.github/workflows/terraform.yml` |
| Estimate costs | `scripts/cost-estimate.sh` |
| Debug a problem | `docs/08-debugging-war-stories.md` |

## Code Complexity Levels

### Beginner-Friendly
- `terraform/environments/dev/terraform.tfvars.example` - Just configuration values
- `terraform/environments/dev/outputs.tf` - Simple output definitions
- `docs/01-fundamentals.md` - Explained with analogies
- `docs/09-visual-explanations.md` - Diagrams and ELI5

### Intermediate
- `terraform/modules/vpc/main.tf` - Standard AWS resources
- `terraform/environments/dev/main.tf` - Module composition
- `terraform/examples/` - Working deployment examples
- `docs/02-internals.md` / `docs/03-project-structure.md`

### Advanced
- `terraform/modules/eks/main.tf` - IAM, security groups, IRSA
- `terraform/modules/addons/karpenter/` - Complex IAM + EventBridge
- `terraform/modules/iam/` - Cross-account access patterns
- `docs/06-security-scaling.md` / `docs/08-debugging-war-stories.md`

### Expert
- `docs/10-interview-questions.md` - Staff-level scenarios
- Production environment with full addon stack
- CI/CD pipeline design
