# Complete Project Index

Quick reference to all files in this project.

## Start Here 🚀

| File | Purpose | Read Time |
|------|---------|-----------|
| `README.md` | Overview & learning path | 10 min |
| `GETTING_STARTED.md` | Step-by-step deployment | 15 min |
| `PROJECT_SUMMARY.md` | What you have & how to use it | 10 min |

## Documentation 📚

### Core Concepts

| File | Topic | Depth | Time |
|------|-------|-------|------|
| `docs/01-fundamentals.md` | Terraform basics | Deep | 1 hour |
| `docs/02-internals.md` | How Terraform works | Deep | 1 hour |
| `docs/04-eks-production.md` | EKS architecture | Very Deep | 1.5 hours |

### Module Documentation

| File | Module | Content |
|------|--------|---------|
| `terraform/modules/vpc/README.md` | VPC | Usage, costs, CIDR planning |
| `terraform/environments/dev/README.md` | Dev Environment | Deployment, testing, troubleshooting |

## Terraform Code 🔧

### Infrastructure Modules

#### VPC Module
```
terraform/modules/vpc/
├── main.tf          # Multi-AZ VPC with subnets, NAT, endpoints
├── variables.tf     # 14 configurable parameters
├── outputs.tf       # VPC ID, subnet IDs, etc.
└── README.md        # Usage guide
```

**Lines of code:** ~400
**Resources created:** ~25 (VPC, subnets, gateways, routes)

#### EKS Module
```
terraform/modules/eks/
├── main.tf          # EKS cluster, nodes, security, IRSA
├── variables.tf     # Cluster config, node groups
├── outputs.tf       # Cluster endpoint, OIDC, etc.
└── user_data.sh.tpl # Node bootstrap script
```

**Lines of code:** ~500
**Resources created:** ~15-30 (depends on node groups)

### Add-on Modules

#### AWS Load Balancer Controller
```
terraform/modules/addons/aws-load-balancer-controller/
├── main.tf          # Helm chart + IRSA
├── variables.tf     # Configuration options
├── outputs.tf       # IAM role ARN
└── iam_policy.json  # AWS IAM policy document
```

**Purpose:** Provisions ALB/NLB for Kubernetes Ingress/Services
**Lines of code:** ~150

#### Cluster Autoscaler
```
terraform/modules/addons/cluster-autoscaler/
├── main.tf          # Helm chart + IRSA
├── variables.tf     # Scaling parameters
└── outputs.tf       # IAM role ARN
```

**Purpose:** Auto-scales EKS node groups based on demand
**Lines of code:** ~180

### Environment Configurations

#### Development Environment
```
terraform/environments/dev/
├── main.tf             # Complete stack (VPC + EKS + Add-ons)
├── variables.tf        # All configurable parameters
├── outputs.tf          # Important values
├── backend.tf          # Remote state config
├── terraform.tfvars    # Development values
└── README.md           # Usage guide
```

**Resources created:** ~60-80
**Deploy time:** 15-20 minutes
**Monthly cost:** ~$218

## File Statistics

### By File Type

| Type | Count | Lines of Code |
|------|-------|---------------|
| Terraform (.tf) | 16 | ~2,500 |
| Documentation (.md) | 8 | ~5,000 |
| Templates (.tpl) | 1 | ~5 |
| JSON | 1 | ~200 |
| **Total** | **26** | **~7,705** |

### By Category

| Category | Files | Purpose |
|----------|-------|---------|
| Documentation | 8 | Learning materials |
| Infrastructure Modules | 8 | Reusable VPC/EKS code |
| Add-on Modules | 6 | Kubernetes add-ons |
| Environments | 5 | Deployable configurations |

## Quick Navigation

### I want to...

**Learn Terraform basics**
→ `docs/01-fundamentals.md`

**Understand how Terraform works**
→ `docs/02-internals.md`

**Deploy my first cluster**
→ `GETTING_STARTED.md`

**Understand the architecture**
→ `docs/04-eks-production.md`

**See the code structure**
→ `PROJECT_SUMMARY.md`

**Customize the VPC**
→ `terraform/modules/vpc/variables.tf`

**Add more nodes**
→ `terraform/environments/dev/terraform.tfvars` (edit `node_groups`)

**Add a new add-on**
→ Copy pattern from `terraform/modules/addons/cluster-autoscaler/`

**Understand costs**
→ `terraform/environments/dev/README.md` (Cost section)

**Prepare for interviews**
→ Read all docs in order, then deploy and experiment

## Code Complexity

### Beginner-Friendly
- `terraform/environments/dev/terraform.tfvars` - Just configuration
- `terraform/environments/dev/outputs.tf` - Simple output definitions
- `docs/01-fundamentals.md` - Explained like you're 10

### Intermediate
- `terraform/modules/vpc/main.tf` - Standard AWS resources
- `terraform/environments/dev/main.tf` - Module composition
- `docs/02-internals.md` - Requires focus

### Advanced
- `terraform/modules/eks/main.tf` - Complex IAM, security groups
- `terraform/modules/addons/*/main.tf` - IRSA patterns, Helm
- `docs/04-eks-production.md` - Production patterns

## Testing Checklist

After deploying, verify:

```bash
# Infrastructure
✓ VPC created with correct CIDR
✓ Subnets in multiple AZs
✓ NAT Gateways operational
✓ EKS cluster healthy
✓ Nodes joined cluster

# Commands
kubectl get nodes                    # Should show 2+ nodes
kubectl get pods -A                  # Should show system pods
kubectl get svc -A                   # Should show services

# Add-ons
kubectl get deployment -n kube-system aws-load-balancer-controller
kubectl get deployment -n kube-system cluster-autoscaler

# Functionality
kubectl create deployment nginx --image=nginx
kubectl expose deployment nginx --type=LoadBalancer --port=80
# Wait for LoadBalancer, then test
```

## Modification Patterns

### Add a New Node Group

**File:** `terraform/environments/dev/terraform.tfvars`

```hcl
node_groups = {
  general = { ... }

  # Add this:
  compute = {
    desired_size   = 1
    max_size       = 10
    min_size       = 0
    instance_types = ["c5.2xlarge"]
    capacity_type  = "SPOT"
    labels = {
      workload = "compute-intensive"
    }
  }
}
```

### Add a New Add-on

**1. Create module:**
```
terraform/modules/addons/my-addon/
├── main.tf
├── variables.tf
└── outputs.tf
```

**2. Reference in environment:**

Edit `terraform/environments/dev/main.tf`:

```hcl
module "my_addon" {
  source = "../../modules/addons/my-addon"

  cluster_name      = module.eks.cluster_id
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url

  depends_on = [module.eks]
}
```

### Change Region

**Files to update:**
1. `terraform/environments/dev/terraform.tfvars` - Set `aws_region`
2. `terraform/environments/dev/backend.tf` - Update region in S3/DynamoDB config
3. Re-run `terraform init` to reconfigure backend

## Dependencies

### Terraform Providers

| Provider | Version | Purpose |
|----------|---------|---------|
| `hashicorp/aws` | ~> 5.0 | AWS resources |
| `hashicorp/helm` | ~> 2.11 | Kubernetes add-ons |
| `hashicorp/kubernetes` | ~> 2.23 | Kubernetes resources |

### External Dependencies

- AWS CLI - For authentication
- kubectl - For cluster access
- Helm - For chart management
- jq - For JSON parsing (optional)

## Version Compatibility

| Component | Version | Notes |
|-----------|---------|-------|
| Terraform | >= 1.6.0 | Uses latest features |
| Kubernetes | 1.28 | Configurable |
| AWS Provider | ~> 5.0 | Latest stable |
| Helm Provider | ~> 2.11 | Latest stable |

## Security Considerations

### Secrets in This Repo

✅ **Safe (no secrets in code):**
- All IAM roles use IRSA (no hardcoded keys)
- Passwords use AWS Secrets Manager references
- State file uses encryption at rest

⚠️ **Gitignored (never commit):**
- `*.tfvars` - May contain IPs/names
- `*.tfstate` - Contains resource IDs
- `kubeconfig` - Cluster credentials
- Any `*-secrets.yaml` files

### Before Committing

```bash
# Always check for secrets
git diff

# Ensure .gitignore is working
git status

# Never force-add ignored files
# git add -f terraform.tfstate  # DON'T DO THIS!
```

## Roadmap

### Phase 1 (Current) ✅
- VPC module
- EKS module
- AWS Load Balancer Controller
- Cluster Autoscaler
- Complete documentation

### Phase 2 (Future)
- EBS CSI Driver addon
- EFS CSI Driver addon
- External DNS addon
- Cert-Manager addon
- Metrics Server addon

### Phase 3 (Future)
- Prometheus addon
- Grafana addon
- OpenTelemetry addon
- Fluent Bit addon
- ArgoCD addon

### Phase 4 (Future)
- Interview questions guide
- Visual diagrams
- War stories documentation
- Testing guide
- Security hardening guide

## Support

### Self-Help Resources

1. **Read error messages carefully** - They usually tell you what's wrong
2. **Check AWS Console** - See actual resource state
3. **Use `terraform plan`** - Before every apply
4. **Check logs** - `kubectl logs` and CloudWatch

### Common Issues

| Error | Fix |
|-------|-----|
| "Unauthorized" | Check AWS credentials |
| "Resource already exists" | Import or rename |
| "Timeout waiting for..." | Wait longer or check AWS Console |
| "Invalid CIDR" | Check VPC/subnet CIDR blocks |

## License

This is educational material. Use it, modify it, learn from it, share it.

## Acknowledgments

Built with best practices from:
- AWS EKS Best Practices Guide
- HashiCorp Terraform Documentation
- Kubernetes Documentation
- Real-world production experience
- Community feedback and patterns

---

**Start your journey:** `README.md` → `GETTING_STARTED.md` → Deploy!

**Have questions?** The answers are in the docs. Read them. 📖

**Ready to deploy?** `cd terraform/environments/dev && terraform init` 🚀
