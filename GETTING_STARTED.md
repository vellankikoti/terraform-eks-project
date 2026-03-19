# Getting Started with Terraform EKS

This guide walks you through deploying a production-grade EKS cluster from zero to running applications.

## Prerequisites

### Required Tools

Install these tools before starting:

```bash
# Terraform (macOS)
brew install terraform

# AWS CLI
brew install awscli

# kubectl
brew install kubectl

# Helm
brew install helm

# Optional but helpful
brew install jq      # JSON parsing
brew install k9s     # Kubernetes TUI
brew install tfenv   # Terraform version management
```

### AWS Account Setup

1. **Create AWS Account** (if you don't have one)
   - Visit aws.amazon.com
   - Sign up for free tier

2. **Create IAM User** (don't use root account)

```bash
# Using AWS Console:
# 1. Go to IAM → Users → Add User
# 2. Name: terraform-user
# 3. Enable: Programmatic access
# 4. Attach policies:
#    - AdministratorAccess (for learning - restrict in production!)
# 5. Save the Access Key ID and Secret Access Key
```

3. **Configure AWS CLI**

```bash
aws configure
# AWS Access Key ID: <your-key>
# AWS Secret Access Key: <your-secret>
# Default region: us-east-1
# Default output format: json

# Verify
aws sts get-caller-identity
```

### Budget Alert (Important!)

Set up a billing alert to avoid surprise costs:

```bash
# Go to AWS Console → Billing → Budgets
# Create budget: $100/month
# Set up email alerts at 80% and 100%
```

## Phase 1: Understand the Code (30 minutes)

### 1. Clone and Explore

```bash
# If you're reading this, you already have the code!
cd terraform-project

# Explore the structure
tree -L 3
```

### 2. Read the Documentation

**Start with these (in order):**

1. `README.md` - Overview and learning path
2. `docs/01-fundamentals.md` - Terraform basics
3. `docs/02-internals.md` - How Terraform works
4. `docs/04-eks-production.md` - EKS architecture
5. `terraform/environments/dev/README.md` - Deployment guide

**Time investment:** 2-3 hours of reading = saves you days of mistakes

### 3. Review the Terraform Code

```bash
# VPC module
cat terraform/modules/vpc/main.tf

# EKS module
cat terraform/modules/eks/main.tf

# Development environment
cat terraform/environments/dev/main.tf
```

**Key things to understand:**
- How modules are structured
- How variables flow from environment → module
- How outputs connect modules together

## Phase 2: Deploy Dev Environment (1 hour)

### Step 1: Customize Variables

```bash
cd terraform/environments/dev

# Edit terraform.tfvars
vim terraform.tfvars
```

**Minimum changes:**

```hcl
project_name = "yourname"  # Change this to your name/project

# Restrict public access (optional but recommended)
public_access_cidrs = ["YOUR.IP.ADDRESS.HERE/32"]
```

Get your IP:
```bash
curl ifconfig.me
```

### Step 2: Set Up Remote State (Recommended)

**Why?** Protects your state file and enables team collaboration.

**Option A: Use the bootstrap module (recommended)**

```bash
cd terraform/bootstrap

# Get your AWS account ID
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Deploy the remote state infrastructure
terraform init
terraform apply -var="aws_account_id=${AWS_ACCOUNT_ID}"

# Note the output - it shows the backend configuration to use
terraform output backend_config
```

**Option B: Manual setup**

```bash
export PROJECT_NAME="yourname"
export AWS_REGION="us-east-1"

aws s3api create-bucket \
  --bucket ${PROJECT_NAME}-terraform-state \
  --region ${AWS_REGION}

aws s3api put-bucket-versioning \
  --bucket ${PROJECT_NAME}-terraform-state \
  --versioning-configuration Status=Enabled

aws s3api put-bucket-encryption \
  --bucket ${PROJECT_NAME}-terraform-state \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "AES256"
      }
    }]
  }'

aws dynamodb create-table \
  --table-name ${PROJECT_NAME}-terraform-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region ${AWS_REGION}
```

**Then edit `backend.tf` in your environment:**

```hcl
terraform {
  backend "s3" {
    bucket         = "yourname-terraform-state-123456789012"
    key            = "dev/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "yourname-terraform-locks"
    encrypt        = true
  }
}
```

### Step 3: Initialize Terraform

```bash
terraform init
```

**Expected output:**
```
Initializing modules...
Initializing provider plugins...
- Installing hashicorp/aws v5.x.x...
- Installing hashicorp/helm v2.x.x...
- Installing hashicorp/kubernetes v2.x.x...

Terraform has been successfully initialized!
```

### Step 4: Plan

```bash
terraform plan
```

**Review carefully:**
- How many resources will be created? (~50-70 resources)
- Are the CIDR blocks correct?
- Are the instance types appropriate?

**Expected resources:**
- 1 VPC
- 6 Subnets (2 public, 2 private per AZ)
- 2 NAT Gateways
- 1 Internet Gateway
- Route tables
- 1 EKS cluster
- 2 EKS node groups
- Security groups
- IAM roles and policies
- CloudWatch log groups
- Helm releases (add-ons)

### Step 5: Apply

```bash
terraform apply
```

Type `yes` when prompted.

**⏱️ Time:** 15-20 minutes

**What's happening:**
1. Creating VPC and networking (2-3 min)
2. Creating EKS control plane (10-12 min)
3. Creating node groups (5-7 min)
4. Installing add-ons (2-3 min)

**Grab coffee. Read docs. This is Terraform doing heavy lifting.**

### Step 6: Verify

```bash
# Check Terraform state
terraform output

# Configure kubectl
aws eks update-kubeconfig --region us-east-1 --name yourname-dev

# Check cluster
kubectl get nodes

# Expected output:
# NAME                         STATUS   ROLES    AGE   VERSION
# ip-10-0-10-123.ec2.internal  Ready    <none>   5m    v1.28.x
# ip-10-0-11-124.ec2.internal  Ready    <none>   5m    v1.28.x

# Check add-ons
kubectl get pods -A

# You should see:
# - CoreDNS pods
# - aws-load-balancer-controller
# - cluster-autoscaler
# - kube-proxy
# - aws-node (VPC CNI)
```

**🎉 Success! You have a production-grade EKS cluster.**

## Phase 3: Deploy Your First Application (30 minutes)

### Option A: Simple NGINX with LoadBalancer

```bash
# Create deployment
kubectl create deployment nginx --image=nginx:latest

# Expose with NLB
kubectl expose deployment nginx --port=80 --type=LoadBalancer

# Wait for LoadBalancer (1-2 minutes)
kubectl get svc nginx -w

# Get the URL
export LB_URL=$(kubectl get svc nginx -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "Visit: http://${LB_URL}"

# Test
curl http://${LB_URL}

# Clean up
kubectl delete svc nginx
kubectl delete deployment nginx
```

### Option B: NGINX with ALB Ingress

Create `nginx-ingress.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx
spec:
  replicas: 3
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
      - name: nginx
        image: nginx:latest
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: nginx
spec:
  type: NodePort
  selector:
    app: nginx
  ports:
  - port: 80
    targetPort: 80
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: nginx
  annotations:
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/healthcheck-path: /
spec:
  ingressClassName: alb
  rules:
  - http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: nginx
            port:
              number: 80
```

Deploy:

```bash
kubectl apply -f nginx-ingress.yaml

# Wait for ALB (3-5 minutes)
kubectl get ingress nginx -w

# Get ALB URL
export ALB_URL=$(kubectl get ingress nginx -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "Visit: http://${ALB_URL}"

# Test
curl http://${ALB_URL}

# Clean up
kubectl delete -f nginx-ingress.yaml
```

## Phase 4: Test Cluster Autoscaler (15 minutes)

```bash
# Create a deployment that needs more nodes
kubectl create deployment scale-test \
  --image=nginx \
  --replicas=20

# Each pod requests resources
kubectl set resources deployment scale-test \
  --requests=cpu=500m,memory=512Mi

# Watch nodes scale up (takes 2-3 minutes)
kubectl get nodes -w

# You should see new nodes joining

# Clean up
kubectl delete deployment scale-test

# Watch nodes scale down (takes ~10 minutes based on autoscaler config)
kubectl get nodes -w
```

## Phase 5: Understanding Costs (10 minutes)

### Check Current Costs

```bash
# Go to AWS Console → Cost Explorer
# View costs by service for the last 7 days
```

### Expected Monthly Costs (Dev Environment)

| Service | Cost | Can Optimize? |
|---------|------|---------------|
| EKS Control Plane | $75 | No |
| EC2 (2x t3.medium ON_DEMAND) | ~$60 | Already optimized |
| EC2 (spot nodes when active) | ~$10-30 | Already using SPOT |
| NAT Gateway (2x) | ~$70 | Use 1 AZ to halve |
| EBS Volumes | ~$10 | No |
| Data Transfer | ~$5 | No |
| **Total** | **~$150-200/month** | Destroy when not in use! |

### Cost Optimization Tips

**For development:**

1. **Destroy when not in use**
   ```bash
   terraform destroy
   ```

2. **Use Spot instances**
   ```hcl
   node_groups = {
     general = {
       capacity_type = "SPOT"  # ~70% cheaper
       ...
     }
   }
   ```

3. **Use 1 NAT Gateway** (less HA)
   ```hcl
   az_count = 1  # Use single AZ in dev
   ```

4. **Smaller instances**
   ```hcl
   instance_types = ["t3.small"]  # Instead of t3.medium
   ```

5. **Schedule on/off**
   - Turn off outside work hours
   - Use AWS Instance Scheduler

## Phase 6: Clean Up (5 minutes)

**⚠️ WARNING: This deletes everything!**

```bash
cd terraform/environments/dev

# Review what will be destroyed
terraform plan -destroy

# Destroy
terraform destroy

# Type: yes
```

**Time:** 10-15 minutes

**What's deleted:**
- All EKS resources
- All EC2 instances
- Load balancers
- VPC and networking
- IAM roles
- CloudWatch logs

**What's NOT deleted:**
- S3 state bucket (manual deletion required)
- DynamoDB lock table (manual deletion required)
- EBS snapshots (if any)

**To fully clean up:**

```bash
# Delete state bucket
aws s3 rm s3://yourname-terraform-state --recursive
aws s3api delete-bucket --bucket yourname-terraform-state

# Delete lock table
aws dynamodb delete-table --table-name terraform-locks
```

## Troubleshooting

### Issue: "Error: creating EKS Cluster: UnsupportedAvailabilityZoneException"

**Cause:** Some AZs don't support EKS.

**Solution:**
```hcl
# In terraform.tfvars
az_count = 2  # Use only 2 AZs
```

### Issue: "Error: UnauthorizedOperation"

**Cause:** IAM user doesn't have sufficient permissions.

**Solution:** Attach `AdministratorAccess` policy (or appropriate permissions).

### Issue: Terraform apply stuck

**Cause:** Usually waiting for AWS resources.

**Solution:** Wait. EKS clusters take 10-15 minutes. If stuck >30 min, check AWS Console for errors.

### Issue: kubectl connection refused

**Cause:** kubeconfig not configured.

**Solution:**
```bash
aws eks update-kubeconfig --region us-east-1 --name yourname-dev
```

### Issue: Nodes not joining cluster

**Cause:** Security group or IAM issues.

**Solution:**
```bash
# Check node IAM role
aws iam get-role --role-name yourname-dev-node-role

# Check security groups
aws ec2 describe-security-groups --filters "Name=tag:Name,Values=yourname-dev*"
```

## Next Steps

### Learning Path

1. ✅ Deploy dev environment (you're here!)
2. 📖 Read `docs/01-fundamentals.md` and `docs/02-internals.md`
3. 🛠️ Deploy more add-ons (Prometheus, Grafana, ArgoCD)
4. 🚀 Deploy your application
5. 🔒 Harden security
6. 📊 Set up monitoring and alerting
7. 🔄 Set up CI/CD

### Add More Add-ons

```bash
# Create new addon modules in terraform/modules/addons/
# Examples: prometheus, grafana, external-dns, cert-manager, argocd
```

### Practice Scenarios

1. **Scenario: Application needs more memory**
   - Update node group instance type
   - Apply changes with zero downtime

2. **Scenario: Need GPU nodes**
   - Add new node group with GPU instances
   - Use taints/tolerations

3. **Scenario: Upgrade Kubernetes**
   - Update cluster_version
   - Test in dev first

## Resources

- [AWS EKS Best Practices](https://aws.github.io/aws-eks-best-practices/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [Terraform AWS Provider Docs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [EKS Workshop](https://www.eksworkshop.com/)

## Getting Help

If you're stuck:

1. Check Terraform errors carefully - they usually tell you what's wrong
2. Check AWS Console - see what resources exist
3. Check kubectl logs - `kubectl logs -n kube-system <pod-name>`
4. Google the error message
5. Check GitHub issues for the relevant add-on

---

**You're ready to go! Start with Phase 1 and work your way through.** 🚀

Remember: Mistakes are learning opportunities. Don't be afraid to break things in dev - that's what it's for.
