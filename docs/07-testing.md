# 07 - Testing & Validation: Proving Your Infrastructure Actually Works

> **Goal**: Build a testing strategy that catches misconfigurations before they become 3 AM pages, and a CI/CD pipeline that makes deploying infrastructure boring (in a good way).

---

## Table of Contents

1. [Why Testing Infrastructure is Different](#1-why-testing-infrastructure-is-different)
2. [Static Analysis (The First Line of Defense)](#2-static-analysis-the-first-line-of-defense)
3. [Plan Testing](#3-plan-testing)
4. [Integration Testing with Terratest](#4-integration-testing-with-terratest)
5. [Contract Testing](#5-contract-testing)
6. [CI/CD Pipeline Design](#6-cicd-pipeline-design)
7. [Safe Production Rollouts](#7-safe-production-rollouts)
8. [Drift Detection](#8-drift-detection)
9. [Testing in Practice - This Project](#9-testing-in-practice---this-project)
10. [Common Testing Mistakes](#10-common-testing-mistakes)
11. [Test Yourself Questions](#11-test-yourself-questions)

---

## 1. Why Testing Infrastructure is Different

### The Uncomfortable Truth

You cannot unit test a VPC the way you unit test a Python function. When you call
`add(2, 3)` in code, you get `5` back in milliseconds, no side effects, no cost.
When you call `aws_vpc.main`, you are spinning up real networking primitives in a
real data center. It takes minutes. It costs money. And if your "test" fails
halfway through, you might leave orphaned resources bleeding your account dry.

This is the fundamental tension of infrastructure testing:

- **Application testing** is fast, cheap, and isolated.
- **Infrastructure testing** is slow, expensive, and has real-world side effects.

That does not mean you skip testing. It means you build a strategy that catches
the maximum number of bugs at the cheapest layer and only runs expensive tests
when the cheap ones pass.

### The Testing Pyramid for Infrastructure

Traditional software has the classic unit/integration/e2e pyramid. Infrastructure
has its own version:

```
                         /\
                        /  \
                       / E2E\           Cost: $$$  Time: 30-60 min
                      / Tests \         "Deploy full stack, run smoke tests"
                     /----------\
                    / Integration\      Cost: $$   Time: 10-30 min
                   /    Tests     \     "Deploy single module, validate behavior"
                  /----------------\
                 /   Plan Analysis  \   Cost: $    Time: 1-3 min
                / (plan, cost, policy)\  "Parse plan output, check policies"
               /----------------------\
              /    Static Analysis      \ Cost: Free  Time: seconds
             / (fmt, validate, lint,     \ "Catch errors without touching AWS"
            /   scan, policy-as-code)     \
           /--------------------------------\
```

**The golden rule**: Push testing as far DOWN this pyramid as possible.

Every bug you catch with `tflint` is a bug that does not cost you 15 minutes of
`terraform apply` and `terraform destroy` in a test account.

### War Story: The $14,000 Test Suite

A team I worked with built a comprehensive Terratest suite for their EKS platform.
Every PR spun up a full VPC, EKS cluster, and node group. The tests took 25
minutes and ran on every push. Developers pushed an average of 6 times per PR.
With 30 PRs a week, that was 180 full EKS deployments. NAT Gateways, EKS control
planes, EC2 instances -- all running for 25+ minutes each. First month's bill for
the test account: $14,000.

The fix was layering. They moved 80% of their checks to static analysis, ran plan
tests on every push, and only triggered full integration tests on the final PR
review. Monthly test cost dropped to $900.

---

## 2. Static Analysis (The First Line of Defense)

Static analysis catches bugs without ever calling the AWS API. No resources
created, no money spent, results in seconds. This is where you get the most
return on investment.

### terraform validate -- The Bare Minimum

`terraform validate` checks your HCL for syntax errors and internal consistency.

```bash
$ terraform validate
Success! The configuration is valid.
```

**What it catches:**
- Syntax errors (missing braces, bad references)
- Invalid resource attribute names
- Type mismatches (passing a string where a list is expected)
- Missing required arguments
- References to resources that do not exist

**What it does NOT catch:**
- Invalid AWS values (e.g., `instance_type = "t3.fakesize"`)
- Security misconfigurations (public S3 buckets)
- Missing provider credentials
- Logical errors (wrong CIDR range for your design)

**Think of it this way**: `terraform validate` is like a compiler. It checks that
your code is syntactically correct, not that it does the right thing.

```bash
# Always init before validate (it needs provider schemas)
terraform init -backend=false
terraform validate
```

The `-backend=false` flag is key for CI -- you do not need real backend
credentials just to validate syntax.

### terraform fmt -- Why Formatting Matters in Teams

"Formatting is not important" -- said no one who has reviewed a 500-line PR where
every developer uses different indentation.

```bash
# Check formatting (returns non-zero exit code if files need changes)
terraform fmt -check -recursive

# Auto-fix formatting
terraform fmt -recursive

# Show the diff without changing files
terraform fmt -diff -check -recursive
```

**Why it matters in teams:**
- Eliminates formatting-only diffs in PRs
- Makes `git blame` useful (no "reformatted file" commits)
- Reduces cognitive load during code review
- Enforced by CI, so no one argues about style

### tflint -- Custom Rules and Plugins

`tflint` is where static analysis gets serious. It understands AWS-specific
rules, not just HCL syntax.

```bash
# Install
brew install tflint

# Initialize (downloads plugins)
tflint --init

# Run
tflint --recursive
```

**Configuration** (`.tflint.hcl`):

```hcl
config {
  # Module inspection (slower but catches more)
  call_module_type = "local"
}

# Use the AWS plugin
plugin "aws" {
  enabled = true
  version = "0.32.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}

# Naming conventions
rule "terraform_naming_convention" {
  enabled = true

  variable {
    format = "snake_case"
  }

  resource {
    format = "snake_case"
  }
}

# Require descriptions on variables
rule "terraform_documented_variables" {
  enabled = true
}

# Require descriptions on outputs
rule "terraform_documented_outputs" {
  enabled = true
}

# Flag deprecated syntax
rule "terraform_deprecated_interpolation" {
  enabled = true
}

# Flag unused declarations
rule "terraform_unused_declarations" {
  enabled = true
}
```

**What tflint catches that validate misses:**

```hcl
resource "aws_instance" "web" {
  ami           = "ami-12345678"
  instance_type = "t3.superxlarge"  # tflint: ERROR - invalid instance type
  # terraform validate would say this is fine
}
```

### tfsec / trivy -- Security Scanning

`tfsec` (now part of Trivy) scans your Terraform for security misconfigurations.

```bash
# Install trivy (includes tfsec functionality)
brew install trivy

# Scan Terraform directory
trivy config .

# With severity filter
trivy config --severity HIGH,CRITICAL .

# Output as JSON for CI parsing
trivy config --format json --output results.json .
```

**Real catches it makes:**

```
HIGH: Security group rule allows ingress from 0.0.0.0/0 to port 22
──────────────────────────────────────────────────────────────────
  modules/vpc/security_groups.tf:15-22

CRITICAL: EKS cluster has public endpoint enabled
──────────────────────────────────────────────────
  modules/eks/main.tf:8-25

MEDIUM: S3 bucket does not have versioning enabled
───────────────────────────────────────────────────
  modules/state/main.tf:1-10
```

**Inline suppression** (when you intentionally accept a risk):

```hcl
resource "aws_security_group_rule" "allow_ssh" {
  #trivy:ignore:AVD-AWS-0107 -- SSH restricted to VPN CIDR in production
  type        = "ingress"
  from_port   = 22
  to_port     = 22
  protocol    = "tcp"
  cidr_blocks = [var.vpn_cidr]
}
```

### checkov -- Compliance as Code

Checkov is especially strong at compliance frameworks (CIS, SOC2, HIPAA).

```bash
# Install
pip install checkov

# Scan
checkov -d . --framework terraform

# Only specific checks
checkov -d . --check CKV_AWS_18,CKV_AWS_19

# Skip specific checks
checkov -d . --skip-check CKV_AWS_145

# Output SARIF for GitHub integration
checkov -d . -o sarif > results.sarif
```

**Checkov vs trivy** -- they overlap significantly, but:

| Feature | trivy (tfsec) | checkov |
|---------|---------------|---------|
| Speed | Faster | Slower on large codebases |
| Custom rules | YAML/Rego | Python |
| Compliance mapping | Basic | Excellent (CIS, SOC2, HIPAA) |
| Plan scanning | Yes | Yes |
| Multi-framework | Yes (Docker, K8s) | Yes (ARM, CloudFormation) |
| Suppression | Inline comments | Inline + .checkov.yaml |

Many teams run both. The overlap costs seconds; the unique catches are worth it.

### OPA / Conftest -- Policy as Code

Open Policy Agent lets you write custom rules in Rego. This is where you encode
your organization's specific standards.

```bash
# Install conftest
brew install conftest
```

**Example policy** (`policy/eks.rego`):

```rego
package main

# Deny EKS clusters without encryption
deny[msg] {
  resource := input.resource.aws_eks_cluster[name]
  not resource.encryption_config
  msg := sprintf("EKS cluster '%s' must have encryption enabled", [name])
}

# Deny node groups with public IPs
deny[msg] {
  resource := input.resource.aws_eks_node_group[name]
  resource.remote_access
  msg := sprintf("EKS node group '%s' should not have remote_access (SSH) enabled", [name])
}

# Enforce minimum node count for production
deny[msg] {
  resource := input.resource.aws_eks_node_group[name]
  resource.scaling_config[_].min_size < 2
  msg := sprintf("EKS node group '%s' must have min_size >= 2 for HA", [name])
}

# Require specific tags
deny[msg] {
  resource := input.resource.aws_eks_cluster[name]
  not resource.tags.Environment
  msg := sprintf("EKS cluster '%s' must have an 'Environment' tag", [name])
}
```

**Run it:**

```bash
# Convert Terraform to JSON and test
terraform show -json tfplan > tfplan.json
conftest test tfplan.json -p policy/
```

### Pre-commit Hooks Setup

This is how you automate all of the above so developers cannot skip it.

**`.pre-commit-config.yaml`**:

```yaml
repos:
  - repo: https://github.com/antonbabenko/pre-commit-tf
    rev: v1.96.1
    hooks:
      # Format all Terraform files
      - id: terraform_fmt

      # Validate Terraform configuration
      - id: terraform_validate
        args:
          - --hook-config=--retry-once-with-cleanup=true

      # Lint with tflint
      - id: terraform_tflint
        args:
          - --args=--config=__GIT_WORKING_DIR__/.tflint.hcl

      # Security scanning with trivy
      - id: terraform_trivy
        args:
          - --args=--severity=HIGH,CRITICAL

      # Checkov compliance scanning
      - id: terraform_checkov
        args:
          - --args=--quiet
          - --args=--compact

      # Generate docs (keeps README in sync with variables/outputs)
      - id: terraform_docs
        args:
          - --args=--config=.terraform-docs.yml

  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v4.6.0
    hooks:
      # Prevent large files from being committed
      - id: check-added-large-files
        args: ['--maxkb=500']

      # Prevent committing to main
      - id: no-commit-to-branch
        args: ['--branch', 'main']

      # Check for merge conflict markers
      - id: check-merge-conflict

      # Ensure files end with newline
      - id: end-of-file-fixer

      # Trim trailing whitespace
      - id: trailing-whitespace
```

**Setup for developers:**

```bash
# Install pre-commit
pip install pre-commit

# Install the hooks
pre-commit install

# Run against all files (first time)
pre-commit run --all-files
```

### Tool Comparison Table

```
+---------------+--------+----------+--------+----------+---------+
| Tool          | Speed  | Security | Custom | CI Ready | Cost    |
|               |        | Focus    | Rules  |          |         |
+---------------+--------+----------+--------+----------+---------+
| tf validate   | <1s    | None     | No     | Yes      | Free    |
| tf fmt        | <1s    | None     | No     | Yes      | Free    |
| tflint        | 1-5s   | Low      | Yes    | Yes      | Free    |
| trivy/tfsec   | 2-10s  | High     | Yes    | Yes      | Free    |
| checkov       | 5-30s  | High     | Yes    | Yes      | Free*   |
| OPA/conftest  | 1-5s   | Medium   | Yes    | Yes      | Free    |
+---------------+--------+----------+--------+----------+---------+
  * checkov has a paid tier with additional policies
```

**Recommended stack**: All of them. They run in parallel in CI in under 60 seconds
total. The cost is zero. The bugs they catch save hours.

---

## 3. Plan Testing

### Reading terraform plan Like an Expert

The plan is the most important artifact in the Terraform workflow. Learning to
read it fluently is a core skill.

```bash
# Generate a plan file (binary format, not human readable)
terraform plan -out=tfplan

# View the plan in human-readable format
terraform show tfplan

# View the plan in JSON for programmatic analysis
terraform show -json tfplan > tfplan.json
```

**The symbols you must know:**

```
  + create        A new resource will be created
  - destroy       An existing resource will be destroyed
  ~ update        An existing resource will be modified in-place
-/+ replace       Resource will be destroyed and re-created
  <= read         A data source will be read

  # Forces replacement  <-- THIS IS THE DANGEROUS ONE
```

**The "forces replacement" trap**: Some attribute changes cannot be applied
in-place. AWS has to destroy the old resource and create a new one. For an RDS
instance, that means downtime. For an EKS cluster, that means total destruction
and rebuild.

```
# aws_eks_cluster.main must be replaced
-/+ resource "aws_eks_cluster" "main" {
      ~ name = "prod-cluster" -> "prod-cluster"  # forces replacement
      ...
    }
```

If you see `forces replacement` on a production resource, **stop everything**.
That plan needs human review.

### Plan File Analysis

```bash
# Count resources by action
terraform show -json tfplan | jq '
  [.resource_changes[] | .change.actions[]] |
  group_by(.) |
  map({action: .[0], count: length})
'

# List all resources being destroyed
terraform show -json tfplan | jq '
  [.resource_changes[] |
   select(.change.actions | contains(["delete"])) |
   .address]
'

# Find resources being replaced (DANGER)
terraform show -json tfplan | jq '
  [.resource_changes[] |
   select(.change.actions | contains(["delete", "create"])) |
   .address]
'
```

### Automated Plan Review in CI

```bash
#!/bin/bash
# scripts/plan-review.sh -- Automated plan safety checks

set -euo pipefail

PLAN_JSON="tfplan.json"
terraform show -json tfplan > "$PLAN_JSON"

# Count destructive actions
DESTROYS=$(jq '[.resource_changes[] | select(.change.actions | contains(["delete"]))] | length' "$PLAN_JSON")
REPLACES=$(jq '[.resource_changes[] | select(.change.actions == ["delete","create"])] | length' "$PLAN_JSON")
CREATES=$(jq '[.resource_changes[] | select(.change.actions == ["create"])] | length' "$PLAN_JSON")
UPDATES=$(jq '[.resource_changes[] | select(.change.actions == ["update"])] | length' "$PLAN_JSON")

echo "Plan Summary:"
echo "  Creates:  $CREATES"
echo "  Updates:  $UPDATES"
echo "  Replaces: $REPLACES"
echo "  Destroys: $DESTROYS"

# Safety gates
if [ "$DESTROYS" -gt 5 ]; then
  echo "BLOCKED: Plan destroys more than 5 resources. Manual approval required."
  exit 1
fi

if [ "$REPLACES" -gt 0 ]; then
  echo "WARNING: Plan replaces resources. Check for downtime implications."
  # List the replaced resources
  jq -r '[.resource_changes[] | select(.change.actions == ["delete","create"]) | .address] | .[]' "$PLAN_JSON"
fi

# Check for dangerous resource types being destroyed
DANGEROUS_TYPES=("aws_eks_cluster" "aws_rds_cluster" "aws_db_instance" "aws_s3_bucket")
for dtype in "${DANGEROUS_TYPES[@]}"; do
  DANGEROUS_DESTROYS=$(jq --arg t "$dtype" '[.resource_changes[] | select(.type == $t) | select(.change.actions | contains(["delete"]))] | length' "$PLAN_JSON")
  if [ "$DANGEROUS_DESTROYS" -gt 0 ]; then
    echo "CRITICAL: Plan destroys $DANGEROUS_DESTROYS $dtype resource(s). Blocking apply."
    exit 1
  fi
done

echo "Plan review passed."
```

### Sentinel Policies (HashiCorp Enterprise)

If you use Terraform Cloud or Enterprise, Sentinel provides first-class policy
enforcement. Think of it as OPA specifically designed for Terraform.

```python
# sentinel/restrict-instance-types.sentinel
import "tfplan/v2" as tfplan

allowed_types = ["t3.medium", "t3.large", "t3.xlarge", "m5.large", "m5.xlarge"]

main = rule {
  all tfplan.resource_changes as _, rc {
    rc.type is "aws_instance" and
    rc.change.after.instance_type in allowed_types
  }
}
```

```python
# sentinel/require-tags.sentinel
import "tfplan/v2" as tfplan

required_tags = ["Environment", "Team", "CostCenter"]

main = rule {
  all tfplan.resource_changes as _, rc {
    all required_tags as tag {
      rc.change.after.tags contains tag
    }
  }
}
```

Sentinel runs between `plan` and `apply` in Terraform Cloud. A failing policy
blocks the apply. No exceptions (unless you configure "soft mandatory" policies
that allow override with justification).

### Plan-Based Cost Estimation (Infracost)

You need to know what your changes will cost BEFORE you apply them.

```bash
# Install
brew install infracost

# Auth (free tier available)
infracost auth login

# Generate cost estimate from plan
infracost breakdown --path . --format table

# Compare cost impact of changes
infracost diff --path . --compare-to infracost-base.json
```

**Sample output:**

```
Project: terraform-eks-project

 Name                                     Monthly Qty  Unit         Monthly Cost

 module.eks.aws_eks_cluster.main
 +-- EKS cluster                                  730  hours              $73.00

 module.eks.aws_eks_node_group.workers
 +-- Linux/UNIX usage (t3.large, on-demand)     2,190  hours             $181.54

 module.vpc.aws_nat_gateway.main[0]
 +-- NAT gateway                                  730  hours              $32.85
 +-- Data processed                    Monthly cost depends on usage

 OVERALL TOTAL                                                           $287.39
```

**In CI, post the diff as a PR comment:**

```yaml
# .github/workflows/infracost.yml
- name: Generate Infracost diff
  run: |
    infracost diff \
      --path=. \
      --format=json \
      --compare-to=/tmp/infracost-base.json \
      --out-file=/tmp/infracost-diff.json

- name: Post PR comment
  run: |
    infracost comment github \
      --path=/tmp/infracost-diff.json \
      --repo=$GITHUB_REPOSITORY \
      --pull-request=${{ github.event.pull_request.number }} \
      --github-token=${{ secrets.GITHUB_TOKEN }} \
      --behavior=update
```

### The "Plan Looks Good but Apply Fails" Scenarios

This happens more than anyone admits. Common causes:

**1. Permissions issues:**
The plan ran with admin credentials, but the apply role is missing permissions.
```
Error: creating EKS Cluster: AccessDeniedException
  Plan showed: + aws_eks_cluster.main  (looked fine)
  Apply says:  You don't have eks:CreateCluster permission
```

**2. Resource limits:**
```
Error: creating VPC: VpcLimitExceeded
  You already have 5 VPCs in us-east-1 (default limit)
```

**3. Eventual consistency:**
```
Error: creating Subnet: InvalidVpcID.NotFound
  The VPC was JUST created. AWS hasn't propagated it yet.
  (Terraform usually handles this with retries, but not always)
```

**4. Name collisions:**
```
Error: creating S3 Bucket: BucketAlreadyExists
  Plan said "create" because it wasn't in state.
  But someone created a bucket with the same name manually.
```

**5. Provider bugs:**
```
Error: updating EKS Cluster: InvalidParameterException
  The provider sent a bad API request. Check the provider's GitHub issues.
```

**Mitigation**: Run `terraform plan` AND `terraform apply` with the same
credentials, in the same environment. Use the saved plan file:

```bash
terraform plan -out=tfplan
terraform apply tfplan   # Applies EXACTLY what was planned
```

---

## 4. Integration Testing with Terratest

### What Terratest Is and How It Works

Terratest is a Go library that automates the full lifecycle:

1. Run `terraform init` and `terraform apply` on your module
2. Validate the created infrastructure (make API calls, curl endpoints, etc.)
3. Run `terraform destroy` to clean up

```
┌──────────────────────────────────────────────────────────┐
│                    Terratest Flow                         │
│                                                           │
│   Go Test  ──>  terraform init                           │
│      │              │                                     │
│      │     terraform apply (creates real resources)       │
│      │              │                                     │
│      │     Validation (API calls, HTTP requests)          │
│      │              │                                     │
│      │     terraform destroy (cleans up)                  │
│      │              │                                     │
│      └──>  Pass / Fail                                   │
│                                                           │
│   Total time: 5-30 minutes per test                      │
│   Total cost: Real AWS charges for resource runtime      │
└──────────────────────────────────────────────────────────┘
```

### Writing Your First Test

**Directory structure:**

```
modules/
  vpc/
    main.tf
    variables.tf
    outputs.tf
test/
  vpc_test.go
  eks_test.go
  go.mod
  go.sum
  fixtures/
    vpc/
      main.tf        # Test-specific Terraform config
    eks/
      main.tf
```

**Setup Go module:**

```bash
cd test
go mod init github.com/yourorg/terraform-eks-project/test
go get github.com/gruntwork-io/terratest/modules/terraform
go get github.com/gruntwork-io/terratest/modules/aws
go get github.com/stretchr/testify/assert
```

### Testing VPC Creation

**Test fixture** (`test/fixtures/vpc/main.tf`):

```hcl
provider "aws" {
  region = "us-east-1"
}

module "vpc" {
  source = "../../../modules/vpc"

  project_name    = "test-vpc"
  environment     = "test"
  vpc_cidr        = "10.99.0.0/16"
  public_subnets  = ["10.99.1.0/24", "10.99.2.0/24"]
  private_subnets = ["10.99.10.0/24", "10.99.11.0/24"]
  azs             = ["us-east-1a", "us-east-1b"]
}

output "vpc_id" {
  value = module.vpc.vpc_id
}

output "private_subnet_ids" {
  value = module.vpc.private_subnet_ids
}

output "public_subnet_ids" {
  value = module.vpc.public_subnet_ids
}
```

**Test** (`test/vpc_test.go`):

```go
package test

import (
	"testing"

	"github.com/gruntwork-io/terratest/modules/aws"
	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
)

func TestVPCModule(t *testing.T) {
	t.Parallel()

	awsRegion := "us-east-1"

	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "./fixtures/vpc",
		Vars:         map[string]interface{}{},
		EnvVars: map[string]string{
			"AWS_DEFAULT_REGION": awsRegion,
		},
		// Retry up to 3 times on known retryable errors
		MaxRetries:         3,
		TimeBetweenRetries: 5 * time.Second,
	})

	// CRITICAL: Always schedule destroy, even if apply or tests fail
	defer terraform.Destroy(t, terraformOptions)

	// Deploy the module
	terraform.InitAndApply(t, terraformOptions)

	// Get outputs
	vpcID := terraform.Output(t, terraformOptions, "vpc_id")
	privateSubnetIDs := terraform.OutputList(t, terraformOptions, "private_subnet_ids")
	publicSubnetIDs := terraform.OutputList(t, terraformOptions, "public_subnet_ids")

	// Validate VPC exists
	vpc := aws.GetVpcById(t, vpcID, awsRegion)
	assert.Equal(t, "10.99.0.0/16", vpc.CidrBlock)

	// Validate subnet counts
	assert.Equal(t, 2, len(privateSubnetIDs))
	assert.Equal(t, 2, len(publicSubnetIDs))

	// Validate subnets are in the correct VPC
	for _, subnetID := range privateSubnetIDs {
		subnet := aws.GetSubnetById(t, subnetID, awsRegion)
		assert.Equal(t, vpcID, subnet.VpcId)
	}

	// Validate public subnets have auto-assign public IP
	for _, subnetID := range publicSubnetIDs {
		subnet := aws.GetSubnetById(t, subnetID, awsRegion)
		assert.True(t, subnet.MapPublicIpOnLaunch)
	}

	// Validate subnets are in different AZs (HA check)
	azSet := map[string]bool{}
	for _, subnetID := range privateSubnetIDs {
		subnet := aws.GetSubnetById(t, subnetID, awsRegion)
		azSet[subnet.AvailabilityZone] = true
	}
	assert.True(t, len(azSet) >= 2, "Private subnets must span at least 2 AZs")
}
```

### Testing EKS Cluster

This is a heavy test. It takes 15-25 minutes just for the cluster to become
active. Run this sparingly -- on merges to main, not on every push.

```go
package test

import (
	"fmt"
	"testing"
	"time"

	"github.com/gruntwork-io/terratest/modules/k8s"
	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestEKSCluster(t *testing.T) {
	t.Parallel()

	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "./fixtures/eks",
		Vars: map[string]interface{}{
			"cluster_name": fmt.Sprintf("test-eks-%d", time.Now().Unix()),
			"environment":  "test",
		},
		MaxRetries:         5,
		TimeBetweenRetries: 10 * time.Second,
	})

	defer terraform.Destroy(t, terraformOptions)

	terraform.InitAndApply(t, terraformOptions)

	// Get the kubeconfig
	kubeconfigPath := terraform.Output(t, terraformOptions, "kubeconfig_path")

	// Create kubectl options
	kubectlOptions := k8s.NewKubectlOptions("", kubeconfigPath, "default")

	// Verify cluster is accessible
	nodes := k8s.GetNodes(t, kubectlOptions)
	require.GreaterOrEqual(t, len(nodes), 2, "Cluster must have at least 2 nodes")

	// Verify nodes are Ready
	for _, node := range nodes {
		for _, condition := range node.Status.Conditions {
			if condition.Type == "Ready" {
				assert.Equal(t, "True", string(condition.Status),
					fmt.Sprintf("Node %s is not Ready", node.Name))
			}
		}
	}

	// Verify kube-system pods are running
	pods := k8s.ListPods(t, kubectlOptions, k8s.NewPodListOptions("kube-system"))
	for _, pod := range pods {
		assert.Equal(t, "Running", string(pod.Status.Phase),
			fmt.Sprintf("Pod %s in kube-system is not Running", pod.Name))
	}

	// Verify CoreDNS is running (critical addon)
	k8s.WaitUntilDeploymentAvailable(t, kubectlOptions, "coredns", 60, 10*time.Second)
}
```

### Testing Helm Deployments

```go
func TestHelmAddonDeployments(t *testing.T) {
	t.Parallel()

	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "./fixtures/addons",
	})

	defer terraform.Destroy(t, terraformOptions)
	terraform.InitAndApply(t, terraformOptions)

	kubeconfigPath := terraform.Output(t, terraformOptions, "kubeconfig_path")

	// Test metrics-server
	t.Run("MetricsServer", func(t *testing.T) {
		kubectlOptions := k8s.NewKubectlOptions("", kubeconfigPath, "kube-system")
		k8s.WaitUntilDeploymentAvailable(t, kubectlOptions, "metrics-server", 60, 5*time.Second)

		// Verify metrics API is responding
		output, err := k8s.RunKubectlAndGetOutputE(t, kubectlOptions, "top", "nodes")
		require.NoError(t, err)
		assert.NotEmpty(t, output)
	})

	// Test cluster-autoscaler
	t.Run("ClusterAutoscaler", func(t *testing.T) {
		kubectlOptions := k8s.NewKubectlOptions("", kubeconfigPath, "kube-system")
		k8s.WaitUntilDeploymentAvailable(t, kubectlOptions, "cluster-autoscaler", 60, 5*time.Second)
	})

	// Test AWS Load Balancer Controller
	t.Run("AWSLoadBalancerController", func(t *testing.T) {
		kubectlOptions := k8s.NewKubectlOptions("", kubeconfigPath, "kube-system")
		k8s.WaitUntilDeploymentAvailable(t, kubectlOptions, "aws-load-balancer-controller", 60, 5*time.Second)
	})
}
```

### Parallel Test Execution

```go
// Run tests in parallel to reduce total execution time.
// Each test uses unique resource names to avoid collisions.

func TestVPCModule(t *testing.T) {
	t.Parallel()  // This test runs concurrently with other t.Parallel() tests
	// ...
}

func TestEKSCluster(t *testing.T) {
	t.Parallel()  // Runs at the same time as TestVPCModule
	// ...
}
```

```bash
# Run all tests with 30-minute timeout
cd test
go test -v -timeout 30m

# Run a specific test
go test -v -timeout 30m -run TestVPCModule

# Run with parallelism limit (avoid AWS rate limits)
go test -v -timeout 30m -parallel 2
```

### Test Fixtures and Cleanup

**The double-defer pattern** (belt and suspenders):

```go
func TestWithCleanup(t *testing.T) {
	t.Parallel()

	terraformOptions := &terraform.Options{
		TerraformDir: "./fixtures/vpc",
	}

	// First line of defense: defer destroy
	defer terraform.Destroy(t, terraformOptions)

	// Second line of defense: tag-based cleanup
	defer cleanupByTag(t, "test-vpc", "us-east-1")

	terraform.InitAndApply(t, terraformOptions)
	// ... validations ...
}

func cleanupByTag(t *testing.T, tagValue string, region string) {
	// Use AWS SDK to find and destroy resources with the test tag
	// This catches resources that Terraform state might have lost track of
	t.Log("Running tag-based cleanup as safety net...")
	// Implementation uses aws.GetResourcesByTag() or similar
}
```

### War Story: The "Test Left Resources Running" Disaster ($$$)

An engineer wrote a Terratest that created an EKS cluster, a NAT Gateway, and
three node group instances. The test passed locally. They committed it and went
to lunch.

But in CI, the test hit a Go panic during the validation phase. The `defer
terraform.Destroy()` call never executed because the test binary crashed, not
just the test function. The EKS cluster, NAT Gateway, and three m5.xlarge nodes
kept running. For three weeks. Nobody checked the test account.

Cost: $2,400 for infrastructure that served zero users.

**Preventive measures:**

1. **Nightly cleanup job**: Script that destroys everything in the test account
   older than 24 hours, based on creation time tags.

```bash
#!/bin/bash
# scripts/nuke-test-account.sh
# Run nightly via cron or scheduled CI

# aws-nuke is purpose-built for this
# https://github.com/rebuy-de/aws-nuke
aws-nuke run --config nuke-config.yml --force --no-dry-run
```

2. **Mandatory tags**: Every test resource gets a `CreatedAt` timestamp tag and
   a `TTL` tag.

3. **Budget alarms**: AWS Budgets alert if the test account exceeds $100/day.

4. **Separate AWS account**: Never run tests in production. Ever.

### Terratest Best Practices

```
+--------------------------------------------+-------------------------------------------+
| DO                                         | DO NOT                                    |
+--------------------------------------------+-------------------------------------------+
| Use t.Parallel() on every test             | Run tests sequentially (wastes time)      |
| Use unique names (timestamps/random)       | Use static names (tests collide)          |
| defer Destroy as the FIRST line            | Put Destroy after Apply (might not run)   |
| Use MaxRetries for flaky AWS APIs          | Fail on first transient error             |
| Tag all resources with test metadata       | Create untagged resources                 |
| Run heavy tests only on merge to main      | Run EKS tests on every commit             |
| Set -timeout in go test                    | Let tests run indefinitely                |
| Use terraform.WithDefaultRetryableErrors   | Handle retries manually                   |
+--------------------------------------------+-------------------------------------------+
```

---

## 5. Contract Testing

### Module Interface Contracts

When you publish a module, you are making a contract with its consumers: "Give me
these inputs, and I will give you these outputs." Contract testing verifies that
the contract holds.

```
┌──────────────────┐     Contract     ┌──────────────────┐
│  VPC Module       │ ──────────────> │  EKS Module       │
│                    │                 │                    │
│  Outputs:          │                 │  Inputs:           │
│  - vpc_id          │  must match     │  - vpc_id          │
│  - subnet_ids      │ ─────────────> │  - subnet_ids      │
│  - cidr_block      │                 │  - vpc_cidr        │
└──────────────────┘                 └──────────────────┘
```

### Output Validation

Add validation blocks to your module outputs:

```hcl
# modules/vpc/outputs.tf

output "vpc_id" {
  description = "The ID of the VPC"
  value       = aws_vpc.main.id

  precondition {
    condition     = aws_vpc.main.state == "available"
    error_message = "VPC is not in 'available' state."
  }
}

output "private_subnet_ids" {
  description = "List of private subnet IDs"
  value       = aws_subnet.private[*].id

  precondition {
    condition     = length(aws_subnet.private) >= 2
    error_message = "At least 2 private subnets are required for HA."
  }
}
```

Add validation blocks to your module inputs:

```hcl
# modules/eks/variables.tf

variable "vpc_id" {
  description = "VPC ID where the cluster will be deployed"
  type        = string

  validation {
    condition     = can(regex("^vpc-[a-z0-9]+$", var.vpc_id))
    error_message = "vpc_id must be a valid VPC ID (vpc-xxxxxxxx)."
  }
}

variable "subnet_ids" {
  description = "Subnet IDs for the EKS cluster"
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "At least 2 subnet IDs are required for EKS HA."
  }

  validation {
    condition     = alltrue([for s in var.subnet_ids : can(regex("^subnet-[a-z0-9]+$", s))])
    error_message = "All subnet IDs must be valid (subnet-xxxxxxxx)."
  }
}

variable "cluster_version" {
  description = "Kubernetes version"
  type        = string

  validation {
    condition     = contains(["1.28", "1.29", "1.30", "1.31"], var.cluster_version)
    error_message = "cluster_version must be a supported EKS version."
  }
}
```

### Cross-Module Dependency Testing

Test that modules work together, not just in isolation:

```go
func TestVPCAndEKSIntegration(t *testing.T) {
	t.Parallel()

	// Step 1: Deploy VPC
	vpcOpts := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "./fixtures/vpc",
	})
	defer terraform.Destroy(t, vpcOpts)
	terraform.InitAndApply(t, vpcOpts)

	vpcID := terraform.Output(t, vpcOpts, "vpc_id")
	subnetIDs := terraform.OutputList(t, vpcOpts, "private_subnet_ids")

	// Step 2: Deploy EKS using VPC outputs
	eksOpts := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "./fixtures/eks",
		Vars: map[string]interface{}{
			"vpc_id":     vpcID,
			"subnet_ids": subnetIDs,
		},
	})
	defer terraform.Destroy(t, eksOpts)
	terraform.InitAndApply(t, eksOpts)

	// Step 3: Validate EKS can reach VPC-internal resources
	clusterEndpoint := terraform.Output(t, eksOpts, "cluster_endpoint")
	assert.Contains(t, clusterEndpoint, "eks.amazonaws.com")
}
```

### Version Compatibility Testing

When you bump a module version, test that existing consumers still work:

```go
func TestModuleVersionUpgrade(t *testing.T) {
	t.Parallel()

	// Deploy with the OLD version
	oldOpts := &terraform.Options{
		TerraformDir: "./fixtures/vpc-v1",
	}
	defer terraform.Destroy(t, oldOpts)
	terraform.InitAndApply(t, oldOpts)

	oldVPCID := terraform.Output(t, oldOpts, "vpc_id")
	oldSubnets := terraform.OutputList(t, oldOpts, "private_subnet_ids")

	// Upgrade to the NEW version (same state, different source)
	newOpts := &terraform.Options{
		TerraformDir: "./fixtures/vpc-v2",
	}
	// Run plan and check for destructive changes
	planOutput := terraform.Plan(t, newOpts)

	// The upgrade should NOT destroy the VPC or subnets
	assert.NotContains(t, planOutput, "must be replaced")
	assert.NotContains(t, planOutput, "will be destroyed")

	// Apply the upgrade
	terraform.Apply(t, newOpts)

	// Outputs should remain compatible
	newVPCID := terraform.Output(t, newOpts, "vpc_id")
	newSubnets := terraform.OutputList(t, newOpts, "private_subnet_ids")

	assert.Equal(t, oldVPCID, newVPCID, "VPC ID should not change on upgrade")
	assert.Equal(t, oldSubnets, newSubnets, "Subnet IDs should not change on upgrade")
}
```

---

## 6. CI/CD Pipeline Design

### The Ideal Pipeline

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        CI/CD Pipeline Flow                               │
│                                                                          │
│  PR Created / Updated                                                    │
│       │                                                                  │
│       v                                                                  │
│  ┌─────────┐  ┌──────────┐  ┌──────┐  ┌──────────┐  ┌──────────┐     │
│  │  Lint   │─>│ Validate │─>│ Plan │─>│ Security │─>│   Cost   │     │
│  │  (fmt,  │  │          │  │      │  │  Scan    │  │  Check   │     │
│  │ tflint) │  │          │  │      │  │(trivy,   │  │(infracost│     │
│  │         │  │          │  │      │  │ checkov) │  │          │     │
│  └─────────┘  └──────────┘  └──────┘  └──────────┘  └──────────┘     │
│       5s          5s          1-3m        10-30s        10-30s         │
│                                                                          │
│  All pass ──> PR Comment with plan + cost summary                       │
│                                                                          │
│  PR Approved + Merged to main                                            │
│       │                                                                  │
│       v                                                                  │
│  ┌─────────┐  ┌───────────────┐  ┌─────────┐  ┌──────────────────┐   │
│  │  Plan   │─>│ Manual Gate   │─>│  Apply  │─>│  Smoke Test      │   │
│  │ (prod)  │  │ (approval     │  │  (prod) │  │  (health checks, │   │
│  │         │  │  required)    │  │         │  │   DNS, endpoints) │   │
│  └─────────┘  └───────────────┘  └─────────┘  └──────────────────┘   │
│       1-3m      minutes-hours       5-20m          1-5m               │
└─────────────────────────────────────────────────────────────────────────┘
```

### GitHub Actions Workflow (Complete YAML)

```yaml
# .github/workflows/terraform.yml
name: Terraform CI/CD

on:
  pull_request:
    branches: [main]
    paths:
      - '**.tf'
      - '**.tfvars'
      - '.github/workflows/terraform.yml'
  push:
    branches: [main]
    paths:
      - '**.tf'
      - '**.tfvars'

permissions:
  contents: read
  pull-requests: write
  id-token: write  # For OIDC auth with AWS

env:
  TF_VERSION: "1.9.0"
  AWS_REGION: "us-east-1"
  TF_IN_AUTOMATION: "true"

jobs:
  # ──────────────────────────────────────
  # Stage 1: Static Analysis (runs on PRs)
  # ──────────────────────────────────────
  lint:
    name: Lint & Format
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: ${{ env.TF_VERSION }}

      - name: Terraform Format Check
        run: terraform fmt -check -recursive -diff

      - name: Setup TFLint
        uses: terraform-linters/setup-tflint@v4

      - name: Init TFLint
        run: tflint --init

      - name: Run TFLint
        run: tflint --recursive --format compact

  validate:
    name: Validate
    runs-on: ubuntu-latest
    strategy:
      matrix:
        directory: [environments/staging, environments/production]
    steps:
      - uses: actions/checkout@v4

      - uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: ${{ env.TF_VERSION }}

      - name: Terraform Init
        run: terraform init -backend=false
        working-directory: ${{ matrix.directory }}

      - name: Terraform Validate
        run: terraform validate
        working-directory: ${{ matrix.directory }}

  security:
    name: Security Scan
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Run Trivy
        uses: aquasecurity/trivy-action@master
        with:
          scan-type: config
          scan-ref: .
          severity: HIGH,CRITICAL
          exit-code: 1
          format: table

      - name: Run Checkov
        uses: bridgecrewio/checkov-action@v12
        with:
          directory: .
          framework: terraform
          quiet: true
          soft_fail: false

  # ──────────────────────────────────────
  # Stage 2: Plan (runs on PRs)
  # ──────────────────────────────────────
  plan:
    name: Terraform Plan
    runs-on: ubuntu-latest
    needs: [lint, validate, security]
    if: github.event_name == 'pull_request'
    strategy:
      matrix:
        environment: [staging, production]
    steps:
      - uses: actions/checkout@v4

      - uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: ${{ env.TF_VERSION }}

      - name: Configure AWS Credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::${{ secrets.AWS_ACCOUNT_ID }}:role/terraform-ci
          aws-region: ${{ env.AWS_REGION }}

      - name: Terraform Init
        run: terraform init
        working-directory: environments/${{ matrix.environment }}

      - name: Terraform Plan
        id: plan
        run: |
          terraform plan -no-color -out=tfplan \
            2>&1 | tee plan_output.txt
          terraform show -json tfplan > tfplan.json
        working-directory: environments/${{ matrix.environment }}

      - name: Plan Safety Check
        run: |
          DESTROYS=$(jq '[.resource_changes[] // [] | select(.change.actions | contains(["delete"]))] | length' tfplan.json)
          if [ "$DESTROYS" -gt 5 ]; then
            echo "::error::Plan destroys $DESTROYS resources. Manual review required."
            exit 1
          fi
        working-directory: environments/${{ matrix.environment }}

      - name: Comment PR with Plan
        uses: actions/github-script@v7
        with:
          script: |
            const fs = require('fs');
            const plan = fs.readFileSync(
              'environments/${{ matrix.environment }}/plan_output.txt', 'utf8'
            );
            const truncated = plan.length > 60000
              ? plan.substring(0, 60000) + '\n... (truncated)'
              : plan;

            github.rest.issues.createComment({
              issue_number: context.issue.number,
              owner: context.repo.owner,
              repo: context.repo.repo,
              body: `### Plan: \`${{ matrix.environment }}\`
            \`\`\`
            ${truncated}
            \`\`\``
            });

  cost:
    name: Cost Estimation
    runs-on: ubuntu-latest
    needs: [lint, validate]
    if: github.event_name == 'pull_request'
    steps:
      - uses: actions/checkout@v4

      - name: Setup Infracost
        uses: infracost/actions/setup@v3
        with:
          api-key: ${{ secrets.INFRACOST_API_KEY }}

      - name: Generate Cost Diff
        run: |
          infracost breakdown --path=. \
            --format=json --out-file=/tmp/infracost.json

      - name: Post Cost Comment
        run: |
          infracost comment github \
            --path=/tmp/infracost.json \
            --repo=$GITHUB_REPOSITORY \
            --pull-request=${{ github.event.pull_request.number }} \
            --github-token=${{ secrets.GITHUB_TOKEN }} \
            --behavior=update

  # ──────────────────────────────────────
  # Stage 3: Apply (runs on merge to main)
  # ──────────────────────────────────────
  apply-staging:
    name: Apply to Staging
    runs-on: ubuntu-latest
    needs: [lint, validate, security]
    if: github.ref == 'refs/heads/main' && github.event_name == 'push'
    environment: staging  # Requires environment approval in GitHub
    steps:
      - uses: actions/checkout@v4

      - uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: ${{ env.TF_VERSION }}

      - name: Configure AWS Credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::${{ secrets.AWS_ACCOUNT_ID }}:role/terraform-deploy
          aws-region: ${{ env.AWS_REGION }}

      - name: Terraform Init
        run: terraform init
        working-directory: environments/staging

      - name: Terraform Apply
        run: terraform apply -auto-approve -input=false
        working-directory: environments/staging

  smoke-test-staging:
    name: Smoke Test (Staging)
    runs-on: ubuntu-latest
    needs: [apply-staging]
    steps:
      - uses: actions/checkout@v4

      - name: Configure AWS Credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::${{ secrets.AWS_ACCOUNT_ID }}:role/terraform-ci
          aws-region: ${{ env.AWS_REGION }}

      - name: Run Smoke Tests
        run: |
          chmod +x scripts/smoke-test.sh
          ./scripts/smoke-test.sh staging

  apply-production:
    name: Apply to Production
    runs-on: ubuntu-latest
    needs: [smoke-test-staging]
    environment: production  # Separate approval gate
    steps:
      - uses: actions/checkout@v4

      - uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: ${{ env.TF_VERSION }}

      - name: Configure AWS Credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::${{ secrets.AWS_ACCOUNT_ID }}:role/terraform-deploy-prod
          aws-region: ${{ env.AWS_REGION }}

      - name: Terraform Init
        run: terraform init
        working-directory: environments/production

      - name: Terraform Plan (Final check)
        run: terraform plan -out=tfplan -input=false
        working-directory: environments/production

      - name: Terraform Apply
        run: terraform apply tfplan
        working-directory: environments/production

  smoke-test-production:
    name: Smoke Test (Production)
    runs-on: ubuntu-latest
    needs: [apply-production]
    steps:
      - uses: actions/checkout@v4

      - name: Configure AWS Credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::${{ secrets.AWS_ACCOUNT_ID }}:role/terraform-ci
          aws-region: ${{ env.AWS_REGION }}

      - name: Run Smoke Tests
        run: |
          chmod +x scripts/smoke-test.sh
          ./scripts/smoke-test.sh production
```

### Branch Protection Rules

Configure these in GitHub repository settings:

```
Branch: main
  [x] Require a pull request before merging
      [x] Require approvals: 1 (2 for production changes)
      [x] Dismiss stale PR approvals when new commits are pushed
  [x] Require status checks to pass before merging
      Required checks:
        - Lint & Format
        - Validate (staging)
        - Validate (production)
        - Security Scan
        - Terraform Plan (staging)
        - Terraform Plan (production)
        - Cost Estimation
  [x] Require conversation resolution before merging
  [x] Do not allow bypassing the above settings
```

### Environment Promotion Strategy

```
Feature Branch ──> PR ──> main ──> staging ──> production
                    │                  │            │
               Code review        Auto-deploy   Manual gate
               Plan review        Smoke test    Smoke test
               Cost check
```

**Key principle**: The same Terraform code is applied to staging first. If staging
is healthy after smoke tests, the same code is applied to production. You never
skip staging. If you are tempted to "just apply this quick fix to prod," remember
the last time someone said that.

### Manual Approval Gates

GitHub Environments provide native approval gates:

1. Go to Settings > Environments > production
2. Add required reviewers (2+ for production)
3. Add deployment branch rule (only `main`)
4. Optional: add wait timer (e.g., 15 minutes after staging passes)

The pipeline will pause at the `apply-production` job and wait for approval.
The approver sees the plan output in the PR and the staging smoke test results.

### Terraform Cloud / Enterprise Integration

If you use Terraform Cloud, replace the GitHub Actions apply steps with:

```yaml
      - name: Upload Configuration
        uses: hashicorp/tfc-workflows-github/actions/upload-configuration@v1
        id: upload
        with:
          workspace: ${{ env.TF_WORKSPACE }}
          directory: environments/production

      - name: Create Run
        uses: hashicorp/tfc-workflows-github/actions/create-run@v1
        id: run
        with:
          workspace: ${{ env.TF_WORKSPACE }}
          configuration_version: ${{ steps.upload.outputs.configuration_version_id }}
```

Terraform Cloud adds Sentinel policies, cost estimation, and a UI for reviewing
plans -- all built in.

---

## 7. Safe Production Rollouts

### Blue/Green Infrastructure Deployment

Blue/green for infrastructure means maintaining two parallel environments and
switching traffic between them.

```
                   ┌─────────────────┐
                   │   Route 53 /    │
                   │   Load Balancer │
                   └────────┬────────┘
                            │
                   Weighted routing
                   ┌────────┴────────┐
                   │                  │
            ┌──────┴──────┐   ┌──────┴──────┐
            │  BLUE (v1)  │   │ GREEN (v2)  │
            │  EKS + VPC  │   │  EKS + VPC  │
            │  (current)  │   │  (new)      │
            │  100% traffic│   │  0% traffic │
            └─────────────┘   └─────────────┘
                                    │
                          After validation,
                          shift traffic:
                          BLUE: 0%, GREEN: 100%
```

**Implementation with Terraform:**

```hcl
variable "active_cluster" {
  description = "Which cluster gets traffic: blue or green"
  type        = string
  default     = "blue"

  validation {
    condition     = contains(["blue", "green"], var.active_cluster)
    error_message = "active_cluster must be 'blue' or 'green'."
  }
}

module "eks_blue" {
  source          = "../modules/eks"
  cluster_name    = "${var.project}-blue"
  cluster_version = "1.29"
  # ...
}

module "eks_green" {
  source          = "../modules/eks"
  cluster_name    = "${var.project}-green"
  cluster_version = "1.30"
  # ...
}

# Route traffic to the active cluster
resource "aws_lb_target_group_attachment" "active" {
  target_group_arn = aws_lb_target_group.main.arn
  target_id        = var.active_cluster == "blue" ? module.eks_blue.node_group_asg : module.eks_green.node_group_asg
}
```

**The upgrade process:**

1. Deploy new version to GREEN (inactive cluster)
2. Run smoke tests against GREEN directly
3. Shift 10% traffic to GREEN (canary)
4. Monitor for 30 minutes
5. Shift 100% traffic to GREEN
6. Keep BLUE running for 24 hours (rollback safety net)
7. Destroy BLUE

**The catch**: This doubles your infrastructure cost during the transition.
For EKS clusters, that is significant. Reserve this strategy for major version
upgrades (e.g., Kubernetes 1.29 to 1.30), not routine changes.

### Canary Deployments with Terraform

For less dramatic changes, use weighted routing:

```hcl
resource "aws_route53_record" "api" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "api.example.com"
  type    = "A"

  # Canary: 5% to new, 95% to current
  weighted_routing_policy {
    weight = var.canary_enabled ? 95 : 100
  }

  set_identifier = "current"
  alias {
    name                   = module.alb_current.dns_name
    zone_id                = module.alb_current.zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "api_canary" {
  count   = var.canary_enabled ? 1 : 0
  zone_id = aws_route53_zone.main.zone_id
  name    = "api.example.com"
  type    = "A"

  weighted_routing_policy {
    weight = 5
  }

  set_identifier = "canary"
  alias {
    name                   = module.alb_canary.dns_name
    zone_id                = module.alb_canary.zone_id
    evaluate_target_health = true
  }
}
```

### Feature Flags for Infrastructure

Use Terraform variables as feature flags:

```hcl
variable "enable_new_node_group" {
  description = "Feature flag: deploy the new Graviton-based node group"
  type        = bool
  default     = false
}

module "node_group_graviton" {
  count  = var.enable_new_node_group ? 1 : 0
  source = "../modules/node-group"

  instance_types = ["m7g.large"]
  # ...
}
```

**Rollout**: Set `enable_new_node_group = true` in staging first, test for a
week, then enable in production. If anything breaks, set it back to `false`.

### Rollback Strategies

**Option 1: Git revert (cleanest)**
```bash
git revert HEAD
# Creates a new commit that undoes the last change
# Push to main, pipeline applies the reverted state
```

**Option 2: Terraform workspace rollback**
```bash
# If you saved the previous plan/state
terraform apply -target=module.eks previous-known-good.tfplan
```

**Option 3: Manual state surgery (last resort)**
```bash
# Remove a problematic resource from state
terraform state rm module.eks.aws_eks_addon.broken_addon

# Move a resource (e.g., after refactoring)
terraform state mv module.old_name.aws_vpc.main module.new_name.aws_vpc.main

# Import a manually-created resource into state
terraform import module.vpc.aws_vpc.main vpc-abc123def
```

### The "Apply Failed Halfway" Disaster Recovery

This is the nightmare scenario. Terraform applied 30 out of 50 resources, then
hit an error. Now your infrastructure is in an inconsistent state.

**What happens:**
```
module.vpc.aws_vpc.main: Creation complete
module.vpc.aws_subnet.public[0]: Creation complete
module.vpc.aws_subnet.public[1]: Creation complete
module.vpc.aws_nat_gateway.main[0]: Creation complete
module.vpc.aws_nat_gateway.main[1]: Still creating... [3m elapsed]
module.vpc.aws_nat_gateway.main[1]: Still creating... [5m elapsed]

Error: error creating NAT Gateway: NatGatewayLimitExceeded

  Terraform has saved the state. Re-run terraform apply to resume.
```

**Recovery steps:**

1. **Do not panic.** Terraform saved the state. It knows what was created.

2. **Read the state:**
   ```bash
   terraform state list
   # Shows which resources exist in state
   ```

3. **Fix the root cause** (request NAT Gateway limit increase, fix the config).

4. **Re-run apply:**
   ```bash
   terraform apply
   # Terraform will skip already-created resources and resume
   ```

5. **If the state is corrupted**, pull it and inspect:
   ```bash
   terraform state pull > state-backup.json
   # Manually inspect, then:
   terraform state push state-fixed.json
   ```

**Golden rule**: Always have state backups. If you use S3 backend with versioning
enabled, every state change creates a new version. You can roll back to any
previous state version through the S3 console.

### State Surgery Reference

```bash
# List all resources in state
terraform state list

# Show details of a specific resource
terraform state show module.vpc.aws_vpc.main

# Remove a resource from state (does NOT destroy the real resource)
terraform state rm module.vpc.aws_eip.nat[1]

# Move a resource (rename without destroy/create)
terraform state mv \
  module.vpc.aws_subnet.private \
  module.networking.aws_subnet.private

# Import an existing resource into state
terraform import module.vpc.aws_vpc.main vpc-0abc123def456

# Pull entire state to local file
terraform state pull > terraform.tfstate.backup

# Push state back (DANGEROUS -- use only for recovery)
terraform state push terraform.tfstate.fixed
```

---

## 8. Drift Detection

### What Is Drift?

Drift is when the actual state of your infrastructure diverges from what
Terraform expects. Someone clicked in the AWS console. An automated process
changed a setting. A Lambda function modified a security group.

Drift is inevitable in any non-trivial environment. The question is not "will it
happen" but "how fast will you detect it."

### Scheduled Plan Runs

The simplest drift detection: run `terraform plan` on a schedule and alert if
there are changes.

```yaml
# .github/workflows/drift-detection.yml
name: Drift Detection

on:
  schedule:
    # Run every 6 hours
    - cron: '0 */6 * * *'
  workflow_dispatch:  # Allow manual trigger

jobs:
  detect-drift:
    name: Check for Drift
    runs-on: ubuntu-latest
    strategy:
      matrix:
        environment: [staging, production]
    steps:
      - uses: actions/checkout@v4

      - uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: ${{ env.TF_VERSION }}

      - name: Configure AWS Credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::${{ secrets.AWS_ACCOUNT_ID }}:role/terraform-readonly
          aws-region: us-east-1

      - name: Terraform Init
        run: terraform init
        working-directory: environments/${{ matrix.environment }}

      - name: Detect Drift
        id: drift
        run: |
          set +e
          terraform plan -detailed-exitcode -input=false \
            2>&1 | tee plan_output.txt
          EXIT_CODE=$?
          set -e

          if [ $EXIT_CODE -eq 0 ]; then
            echo "drift=false" >> "$GITHUB_OUTPUT"
            echo "No drift detected."
          elif [ $EXIT_CODE -eq 2 ]; then
            echo "drift=true" >> "$GITHUB_OUTPUT"
            echo "DRIFT DETECTED!"
          else
            echo "drift=error" >> "$GITHUB_OUTPUT"
            echo "Plan failed!"
            exit 1
          fi
        working-directory: environments/${{ matrix.environment }}

      - name: Alert on Drift
        if: steps.drift.outputs.drift == 'true'
        run: |
          # Send to Slack
          PLAN=$(cat environments/${{ matrix.environment }}/plan_output.txt | head -100)
          curl -X POST "${{ secrets.SLACK_WEBHOOK }}" \
            -H 'Content-Type: application/json' \
            -d "{
              \"text\": \"Drift detected in ${{ matrix.environment }}!\",
              \"blocks\": [{
                \"type\": \"section\",
                \"text\": {
                  \"type\": \"mrkdwn\",
                  \"text\": \"*Drift detected in \`${{ matrix.environment }}\`*\n\`\`\`${PLAN}\`\`\`\"
                }
              }]
            }"
```

**Key detail**: The `-detailed-exitcode` flag makes `terraform plan` return:
- `0`: No changes (no drift)
- `1`: Error
- `2`: Changes detected (drift!)

### AWS Config Rules

For real-time drift detection (not just every 6 hours), use AWS Config:

```hcl
resource "aws_config_config_rule" "vpc_sg_open_only_to_authorized_ports" {
  name = "vpc-sg-open-only-to-authorized-ports"

  source {
    owner             = "AWS"
    source_identifier = "VPC_SG_OPEN_ONLY_TO_AUTHORIZED_PORTS"
  }

  input_parameters = jsonencode({
    authorizedTcpPorts = "443,80"
  })
}

resource "aws_config_config_rule" "eks_cluster_oldest_version" {
  name = "eks-cluster-oldest-supported-version"

  source {
    owner             = "AWS"
    source_identifier = "EKS_CLUSTER_OLDEST_SUPPORTED_VERSION"
  }
}

# SNS topic for Config notifications
resource "aws_sns_topic" "config_alerts" {
  name = "config-drift-alerts"
}

resource "aws_config_delivery_channel" "main" {
  name           = "default"
  s3_bucket_name = aws_s3_bucket.config.id
  sns_topic_arn  = aws_sns_topic.config_alerts.arn

  snapshot_delivery_properties {
    delivery_frequency = "Six_Hours"
  }
}
```

AWS Config detects changes in real time and can trigger Lambda functions or SNS
notifications. This is complementary to Terraform plan-based detection -- Config
catches changes the moment they happen, while plan-based detection catches drift
in the Terraform model.

### terraform refresh Patterns

`terraform refresh` updates the state file to match reality without making any
changes. It is useful for detection but has been largely superseded by
`terraform plan -refresh-only`.

```bash
# Modern approach (safer, shows what would change in state)
terraform plan -refresh-only

# If you want to accept the refreshed state
terraform apply -refresh-only
```

**When to use refresh-only:**
- After someone made an intentional manual change you want to accept
- After disaster recovery when you rebuilt resources manually
- When importing a large number of pre-existing resources

### Handling Intentional vs Unintentional Drift

Not all drift is bad. Sometimes a team intentionally changes something and
Terraform has not caught up yet.

**Pattern: Drift triage**

```
Drift detected
     │
     v
Is the change in the ignore list?  ──> Yes ──> Suppress alert
     │
     No
     │
     v
Is there a Jira ticket for this change?  ──> Yes ──> Update Terraform code
     │
     No
     │
     v
ALERT: Unauthorized change detected
     │
     v
Revert with terraform apply (restore desired state)
```

**Use lifecycle ignore_changes for known drift:**

```hcl
resource "aws_autoscaling_group" "workers" {
  # ... config ...

  lifecycle {
    ignore_changes = [
      desired_capacity,  # Cluster Autoscaler changes this
    ]
  }
}

resource "aws_eks_node_group" "main" {
  # ... config ...

  lifecycle {
    ignore_changes = [
      scaling_config[0].desired_size,  # Managed by Karpenter
    ]
  }
}
```

---

## 9. Testing in Practice -- This Project

### How to Test Our VPC Module

```bash
# Step 1: Static analysis
cd modules/vpc
terraform init -backend=false
terraform validate
terraform fmt -check
tflint
trivy config .

# Step 2: Plan test (requires AWS credentials)
cd environments/staging
terraform init
terraform plan -out=tfplan
terraform show -json tfplan | jq '.resource_changes | length'
# Inspect the plan for unexpected changes

# Step 3: Integration test with Terratest
cd test
go test -v -timeout 20m -run TestVPCModule
```

**What to validate in the VPC:**
- VPC CIDR is correct
- Correct number of subnets in each tier (public, private)
- Subnets span multiple AZs
- NAT Gateways are created (one per AZ)
- Route tables have correct routes (0.0.0.0/0 via NAT for private, via IGW for public)
- EKS-required tags are present on subnets
- Flow logs are enabled

### How to Test Our EKS Module

```bash
# Static analysis (fast, free)
cd modules/eks
terraform init -backend=false
terraform validate
trivy config --severity HIGH,CRITICAL .

# Plan test
cd environments/staging
terraform plan -target=module.eks -out=tfplan
# Check: no replacement of cluster, node groups have correct instance types

# Integration test (slow, costly -- run only on merge)
cd test
go test -v -timeout 45m -run TestEKSCluster
```

**What to validate in EKS:**
- Cluster is ACTIVE
- Cluster version matches configuration
- OIDC provider is configured (required for IRSA)
- Node groups have correct instance types
- Nodes are Ready
- CoreDNS, kube-proxy, and vpc-cni addons are running
- Security groups allow correct traffic patterns
- Cluster endpoint access is configured as expected

### How to Validate Addon Deployments

```bash
# After applying addons, verify they are running
kubectl get deployments -n kube-system

# Expected output:
# NAME                           READY   UP-TO-DATE   AVAILABLE
# aws-load-balancer-controller   2/2     2            2
# cluster-autoscaler             1/1     1            1
# coredns                        2/2     2            2
# metrics-server                 1/1     1            1
```

### Smoke Test Script

```bash
#!/bin/bash
# scripts/smoke-test.sh
# Usage: ./smoke-test.sh <environment>

set -euo pipefail

ENVIRONMENT="${1:?Usage: smoke-test.sh <environment>}"
FAILURES=0

echo "Running smoke tests for: $ENVIRONMENT"
echo "================================================"

# Test 1: EKS cluster is reachable
echo -n "Test 1: EKS cluster API reachable... "
if kubectl cluster-info --context "arn:aws:eks:us-east-1:ACCOUNT:cluster/${ENVIRONMENT}-cluster" > /dev/null 2>&1; then
  echo "PASS"
else
  echo "FAIL"
  FAILURES=$((FAILURES + 1))
fi

# Test 2: Nodes are Ready
echo -n "Test 2: All nodes are Ready... "
NOT_READY=$(kubectl get nodes --no-headers | grep -cv "Ready" || true)
if [ "$NOT_READY" -eq 0 ]; then
  echo "PASS"
else
  echo "FAIL ($NOT_READY nodes not ready)"
  FAILURES=$((FAILURES + 1))
fi

# Test 3: kube-system pods are running
echo -n "Test 3: kube-system pods healthy... "
UNHEALTHY=$(kubectl get pods -n kube-system --no-headers | grep -cv "Running\|Completed" || true)
if [ "$UNHEALTHY" -eq 0 ]; then
  echo "PASS"
else
  echo "FAIL ($UNHEALTHY unhealthy pods)"
  FAILURES=$((FAILURES + 1))
fi

# Test 4: CoreDNS is resolving
echo -n "Test 4: CoreDNS resolution... "
if kubectl run dns-test --image=busybox:1.36 --restart=Never --rm -i --wait \
  -- nslookup kubernetes.default.svc.cluster.local > /dev/null 2>&1; then
  echo "PASS"
else
  echo "FAIL"
  FAILURES=$((FAILURES + 1))
fi

# Test 5: Can create and delete a test namespace
echo -n "Test 5: Namespace CRUD... "
if kubectl create namespace smoke-test-$$ > /dev/null 2>&1 && \
   kubectl delete namespace smoke-test-$$ > /dev/null 2>&1; then
  echo "PASS"
else
  echo "FAIL"
  FAILURES=$((FAILURES + 1))
fi

# Test 6: Metrics server responding
echo -n "Test 6: Metrics server... "
if kubectl top nodes > /dev/null 2>&1; then
  echo "PASS"
else
  echo "FAIL"
  FAILURES=$((FAILURES + 1))
fi

# Test 7: AWS Load Balancer Controller is running
echo -n "Test 7: AWS LB Controller... "
LBC_READY=$(kubectl get deployment -n kube-system aws-load-balancer-controller -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
if [ "$LBC_READY" -ge 1 ]; then
  echo "PASS"
else
  echo "FAIL"
  FAILURES=$((FAILURES + 1))
fi

echo "================================================"
echo "Results: $((7 - FAILURES))/7 passed"

if [ "$FAILURES" -gt 0 ]; then
  echo "SMOKE TESTS FAILED"
  exit 1
else
  echo "ALL SMOKE TESTS PASSED"
  exit 0
fi
```

---

## 10. Common Testing Mistakes

### Mistake 1: Testing Implementation Instead of Behavior

**Wrong:**
```go
// Tests that the VPC resource has a specific attribute value
assert.Equal(t, "true", terraform.Output(t, opts, "enable_dns_support"))
```

This tests that you set a Terraform attribute. That is just re-reading your own
config file. Useless.

**Right:**
```go
// Tests that DNS actually resolves inside the VPC
// This tests BEHAVIOR, not implementation
output, err := ssh.CheckSshCommandE(t, host, "nslookup api.internal.example.com")
assert.NoError(t, err)
assert.Contains(t, output, "10.0.")
```

Test what your infrastructure DOES, not how it is configured.

### Mistake 2: Not Cleaning Up Test Resources

We covered this in the Terratest section, but it bears repeating. Every test
function must have `defer terraform.Destroy()` as its FIRST statement after
creating the options. Not the last. The first. Because if `InitAndApply` fails
halfway, the defer still runs.

```go
// WRONG order
func TestBad(t *testing.T) {
    opts := &terraform.Options{TerraformDir: "./fixtures/vpc"}
    terraform.InitAndApply(t, opts)       // If this panics...
    defer terraform.Destroy(t, opts)       // ...this never registers
}

// RIGHT order
func TestGood(t *testing.T) {
    opts := &terraform.Options{TerraformDir: "./fixtures/vpc"}
    defer terraform.Destroy(t, opts)       // Registered FIRST
    terraform.InitAndApply(t, opts)        // If this fails, cleanup still runs
}
```

### Mistake 3: Flaky Tests Due to Eventual Consistency

AWS is eventually consistent. You create a resource, and for a few seconds, some
API calls might not see it yet. This causes tests to fail intermittently.

**Symptoms:**
- "Resource not found" errors 10% of the time
- Tests pass locally but fail in CI
- Re-running the same test makes it pass

**Fixes:**
```go
// Use Terratest's built-in retry
terraform.WithDefaultRetryableErrors(t, opts)

// Or custom retry for specific checks
retry.DoWithRetry(t, "Wait for EKS cluster", 30, 10*time.Second, func() (string, error) {
    cluster, err := aws.GetEksClusterE(t, region, clusterName)
    if err != nil {
        return "", err
    }
    if cluster.Status != "ACTIVE" {
        return "", fmt.Errorf("Cluster status is %s, waiting for ACTIVE", cluster.Status)
    }
    return "Cluster is ACTIVE", nil
})
```

### Mistake 4: Over-Mocking

Some teams try to mock AWS API calls in their Terraform tests. This defeats the
entire purpose of integration testing. If you mock the API, you are testing your
mocks, not your infrastructure.

**The right approach:**
- Use static analysis for "does the config look right" (no AWS needed)
- Use real AWS calls for "does the infrastructure work" (integration tests)
- Use a dedicated test AWS account with budget alarms
- Accept that integration tests are slow -- that is the nature of infrastructure

Mocking has its place in application code. In infrastructure testing, it creates
a false sense of security.

### Mistake 5: Not Testing Destroy

Your module creates resources. Does it also cleanly destroy them? Many teams
never test this until they need to tear down a staging environment and discover
that their module leaves orphaned resources.

**Common destroy failures:**
- S3 buckets that are not empty (Terraform cannot delete non-empty buckets by
  default)
- Security groups referenced by other resources
- IAM roles with attached policies
- Resources with deletion protection enabled

```go
func TestDestroyIsClean(t *testing.T) {
    opts := &terraform.Options{TerraformDir: "./fixtures/full-stack"}
    defer terraform.Destroy(t, opts)

    terraform.InitAndApply(t, opts)

    // ... validation ...

    // Explicitly test destroy
    terraform.Destroy(t, opts)

    // Verify resources are actually gone
    vpcID := terraform.Output(t, opts, "vpc_id")
    _, err := aws.GetVpcByIdE(t, vpcID, "us-east-1")
    assert.Error(t, err, "VPC should not exist after destroy")
}
```

---

## 11. Test Yourself Questions

1. You run `terraform plan` and it shows 0 changes, but the actual infrastructure
   has been modified manually. What happened, and what command would reveal the
   drift?

2. A Terratest integration test creates an EKS cluster, then crashes during the
   validation phase with a Go panic. The `defer terraform.Destroy()` was
   registered. Does the cleanup run? Why or why not?

3. Your CI pipeline runs `trivy config .` and reports a HIGH severity finding:
   "S3 bucket does not have server-side encryption enabled." But you know the
   bucket uses SSE-S3 by default (AWS changed the default in Jan 2023). How do
   you handle this false positive without disabling the scanner entirely?

4. Explain why `terraform plan -out=tfplan` followed by `terraform apply tfplan`
   is safer than running `terraform apply` directly. Give a scenario where the
   results would differ.

5. Your team uses the module interface contract pattern with variable validation
   blocks. A consumer passes `subnet_ids = ["subnet-abc123"]` (only one subnet).
   Your validation requires at least 2 subnets. At what phase does this error
   surface -- validate, plan, or apply? Why does this matter for CI speed?

6. You are implementing blue/green deployment for an EKS cluster upgrade from
   1.29 to 1.30. After shifting traffic to the green cluster, you discover a
   compatibility issue with one of your workloads. Describe your rollback process
   step by step.

7. The drift detection pipeline alerts that an autoscaling group's desired
   capacity changed from 3 to 7. Is this drift intentional or unintentional?
   What Terraform configuration would prevent this from triggering false alarms?

8. A developer proposes adding `terraform apply -auto-approve` to the PR
   pipeline so that every PR automatically deploys to a preview environment.
   What are the risks, and how would you mitigate them?

9. Your `terraform apply` fails after creating 30 out of 50 resources due to an
   AWS service limit. The error is `LimitExceededException`. What do you do?
   Walk through the recovery process.

10. Explain the difference between testing "the VPC has DNS support enabled"
    (implementation test) and "services in the VPC can resolve internal DNS
    names" (behavior test). When would you use each type, and why does the
    distinction matter for long-term maintainability?

---

## Summary: The Testing Checklist

- Set up pre-commit hooks (fmt, validate, tflint, trivy) on day one
- Run security scanning in CI on every PR (trivy + checkov)
- Post plan output and cost estimates as PR comments
- Use policy-as-code (OPA/Conftest or Sentinel) for organizational standards
- Write Terratest integration tests for critical modules (VPC, EKS)
- Run integration tests on merge to main, not on every push
- Implement drift detection on a schedule (every 6 hours minimum)
- Use `lifecycle { ignore_changes }` for known intentional drift
- Always test destroy, not just create
- Maintain a nightly cleanup job for the test account
- Use separate AWS accounts for testing and production

---

## What's Next?

You now have a complete testing strategy that spans from pre-commit hooks to
production smoke tests. You can:
- Catch 80% of issues before they hit AWS
- Review plans and costs before applying
- Validate infrastructure behavior with integration tests
- Detect and respond to drift
- Deploy safely with approval gates and rollback plans

**Next up**: Apply these patterns to your own modules and build a CI/CD pipeline
that makes infrastructure changes boring, predictable, and safe.

That is the entire goal: making infrastructure changes boring.
