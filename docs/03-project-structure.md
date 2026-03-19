# 03 - Project Structure: Battle-Tested Repo Layouts and Module Design

> **Goal**: Learn how to organize Terraform projects so they stay maintainable at scale, avoid state file disasters, and let your team move fast without breaking things.

---

## Table of Contents

1. [Why Structure Matters More Than You Think](#1-why-structure-matters-more-than-you-think)
2. [The Flat File Anti-Pattern](#2-the-flat-file-anti-pattern)
3. [Battle-Tested Repo Layouts](#3-battle-tested-repo-layouts)
4. [Module Design Patterns](#4-module-design-patterns)
5. [Multi-Environment Strategies](#5-multi-environment-strategies)
6. [Monorepo vs Multi-Repo](#6-monorepo-vs-multi-repo)
7. [State File Organization](#7-state-file-organization)
8. [The DRY Principle in Terraform](#8-the-dry-principle-in-terraform)
9. [Anti-Patterns That Will Haunt You](#9-anti-patterns-that-will-haunt-you)
10. [Real-World Examples](#10-real-world-examples)
11. [Test Yourself](#11-test-yourself)

---

## 1. Why Structure Matters More Than You Think

Here is a story that plays out at every company that adopts Terraform without thinking about structure first.

Month 1: One engineer writes a `main.tf` with 50 lines. It creates a VPC and an EC2 instance. Life is good.

Month 3: The file is 400 lines. It creates a VPC, subnets, security groups, an EKS cluster, RDS, and an S3 bucket. Two engineers are working on it. They keep getting merge conflicts.

Month 6: The file is 1,200 lines. Nobody wants to touch it. A junior engineer runs `terraform apply` and accidentally destroys the production database because everything is in a single state file. The incident takes 6 hours to resolve.

Month 12: The team rewrites everything from scratch. They lose two sprints.

**This is not hypothetical.** This is the default trajectory when you treat Terraform project structure as an afterthought.

### The Three Forces That Shape Structure

```
┌─────────────────────────────────────────────────┐
│              PROJECT STRUCTURE                    │
│                                                   │
│   ┌──────────────┐  ┌──────────────┐            │
│   │  BLAST RADIUS │  │ TEAM VELOCITY│            │
│   │               │  │              │            │
│   │ How much can  │  │ How fast can │            │
│   │ break at once?│  │ people ship? │            │
│   └──────┬───────┘  └──────┬───────┘            │
│          │                  │                     │
│          └────────┬─────────┘                     │
│                   │                               │
│          ┌────────┴────────┐                      │
│          │  CODE REUSE     │                      │
│          │                 │                      │
│          │ How much do you │                      │
│          │ copy-paste?     │                      │
│          └─────────────────┘                      │
└─────────────────────────────────────────────────┘
```

Every structural decision is a trade-off between these three forces:

- **Blast radius**: Smaller state files mean less can break at once, but more overhead to manage.
- **Team velocity**: More isolation means fewer merge conflicts, but more boilerplate.
- **Code reuse**: Shared modules reduce duplication, but add coupling between teams.

There is no single correct answer. But there are patterns that work and anti-patterns that predictably fail.

---

## 2. The Flat File Anti-Pattern

Before we look at good structures, let us understand the most common bad one.

### The Single-Directory Disaster

```
terraform-project/
  main.tf          # 2000 lines, everything in here
  variables.tf     # 300 variables
  outputs.tf       # 100 outputs
  terraform.tfvars # secrets accidentally committed
```

### Why This Breaks

**Problem 1: Single blast radius.** Every `terraform apply` touches every resource. Change a security group rule? Terraform also evaluates your database, your Kubernetes cluster, and your DNS records. One wrong move and everything is at risk.

**Problem 2: State file contention.** With remote state locking, only one person can run `terraform plan` at a time for the entire infrastructure. Your team of five engineers is now a team of one.

**Problem 3: Plan times explode.** Terraform must call every cloud API to refresh state for every resource. A project with 500 resources can take 10-15 minutes just to plan.

**Problem 4: Cognitive overload.** No human can hold 2,000 lines of HCL in their head. People stop reading the code and start praying their changes work.

> **What breaks in production**: A developer modifies a security group and runs `terraform apply`. Terraform's state refresh detects drift on an unrelated RDS instance (someone changed a parameter via the console). Terraform tries to "fix" the drift, which triggers a database restart. Production goes down for 20 minutes. The security group change was fine -- the blast radius was the problem.

---

## 3. Battle-Tested Repo Layouts

### Layout 1: Environment Directories (Most Common)

This is the layout that works for 80% of teams. Each environment gets its own directory with its own state file.

```
terraform-eks-project/
├── modules/
│   ├── vpc/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── eks/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── rds/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   └── monitoring/
│       ├── main.tf
│       ├── variables.tf
│       └── outputs.tf
├── environments/
│   ├── dev/
│   │   ├── main.tf           # Calls modules with dev params
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   ├── terraform.tfvars
│   │   └── backend.tf        # Dev state bucket
│   ├── staging/
│   │   ├── main.tf           # Calls modules with staging params
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   ├── terraform.tfvars
│   │   └── backend.tf        # Staging state bucket
│   └── production/
│       ├── main.tf           # Calls modules with prod params
│       ├── variables.tf
│       ├── outputs.tf
│       ├── terraform.tfvars
│       └── backend.tf        # Prod state bucket
└── global/
    ├── iam/
    │   ├── main.tf
    │   └── backend.tf
    └── dns/
        ├── main.tf
        └── backend.tf
```

**Why this works:**

- Each environment has its own state file. You cannot accidentally destroy prod while working on dev.
- Each environment can diverge intentionally. Staging might have smaller instances.
- The `global/` directory holds resources that span environments (IAM roles, DNS zones).
- Modules are shared, so you are not copy-pasting VPC code three times.

**The trade-off:** You have some duplication in the environment directories. Each one has a `main.tf` that calls the same modules. This is intentional -- it makes each environment independently deployable.

### Layout 2: Component-Based (For Larger Teams)

When your infrastructure grows beyond what a single state file per environment can handle, split by component within each environment.

```
terraform-eks-project/
├── modules/
│   ├── vpc/
│   ├── eks/
│   ├── rds/
│   └── monitoring/
├── environments/
│   ├── production/
│   │   ├── networking/        # State file 1: VPC, subnets, routes
│   │   │   ├── main.tf
│   │   │   ├── backend.tf
│   │   │   └── outputs.tf
│   │   ├── compute/           # State file 2: EKS, node groups
│   │   │   ├── main.tf
│   │   │   ├── backend.tf
│   │   │   └── data.tf       # Reads networking outputs via remote state
│   │   ├── database/          # State file 3: RDS, ElastiCache
│   │   │   ├── main.tf
│   │   │   ├── backend.tf
│   │   │   └── data.tf
│   │   └── monitoring/        # State file 4: CloudWatch, Grafana
│   │       ├── main.tf
│   │       ├── backend.tf
│   │       └── data.tf
│   └── staging/
│       └── ... (same structure)
└── global/
    ├── iam/
    └── dns/
```

**When to use this:**

- Your infrastructure has 200+ resources per environment
- Different teams own different components (network team, platform team, application team)
- You need to apply changes to compute without touching the database
- Plan times exceed 5 minutes

**The data source pattern** ties components together:

```hcl
# environments/production/compute/data.tf
data "terraform_remote_state" "networking" {
  backend = "s3"
  config = {
    bucket = "mycompany-terraform-state"
    key    = "production/networking/terraform.tfstate"
    region = "us-east-1"
  }
}

# Now use it
module "eks" {
  source = "../../../modules/eks"

  vpc_id     = data.terraform_remote_state.networking.outputs.vpc_id
  subnet_ids = data.terraform_remote_state.networking.outputs.private_subnet_ids
}
```

> **What breaks in production**: When using remote state data sources, if someone deletes an output from the networking component that the compute component depends on, the next `terraform plan` on compute will fail. Always treat module outputs as a contract -- never remove them without checking downstream consumers.

### Layout 3: Terragrunt-Based (For Maximum DRY)

Terragrunt is a thin wrapper around Terraform that eliminates the boilerplate of Layout 1 and Layout 2.

```
terraform-eks-project/
├── modules/
│   ├── vpc/
│   ├── eks/
│   └── rds/
├── terragrunt.hcl              # Root config (backend, provider defaults)
├── environments/
│   ├── _env/
│   │   └── common.hcl          # Shared variables across envs
│   ├── production/
│   │   ├── env.hcl             # environment = "production"
│   │   ├── networking/
│   │   │   └── terragrunt.hcl  # Just: source + inputs
│   │   ├── compute/
│   │   │   └── terragrunt.hcl
│   │   └── database/
│   │       └── terragrunt.hcl
│   └── staging/
│       ├── env.hcl
│       ├── networking/
│       │   └── terragrunt.hcl
│       └── ...
```

A typical Terragrunt component file is tiny:

```hcl
# environments/production/compute/terragrunt.hcl
include "root" {
  path = find_in_parent_folders()
}

include "env" {
  path = "${get_terragrunt_dir()}/../../_env/common.hcl"
}

terraform {
  source = "../../../modules/eks"
}

dependency "networking" {
  config_path = "../networking"
}

inputs = {
  vpc_id     = dependency.networking.outputs.vpc_id
  subnet_ids = dependency.networking.outputs.private_subnet_ids

  cluster_version = "1.28"
  node_count      = 5
}
```

**Advantages:**

- Backend configuration is auto-generated. No copy-pasting `backend.tf` files.
- Dependencies are explicit and Terragrunt handles the apply order.
- `terragrunt run-all apply` deploys an entire environment in dependency order.

**Disadvantages:**

- Another tool to learn and maintain.
- IDE support is weaker than pure Terraform.
- Debugging is harder -- you are debugging Terraform through Terragrunt.

---

## 4. Module Design Patterns

Modules are the functions of Terraform. Getting them right is the single highest-leverage design decision you will make.

### The Three Types of Modules

```
┌─────────────────────────────────────────────────────────────┐
│                     MODULE HIERARCHY                          │
│                                                               │
│  ┌───────────────────────────────────────────────────────┐  │
│  │              COMPOSITION MODULES                       │  │
│  │  "Deploy a complete production EKS environment"        │  │
│  │  Calls multiple service modules                        │  │
│  │  Lives in: environments/production/main.tf             │  │
│  └───────────────────────┬───────────────────────────────┘  │
│                          │                                    │
│          ┌───────────────┼───────────────┐                   │
│          v               v               v                   │
│  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐        │
│  │SERVICE MODULE│ │SERVICE MODULE│ │SERVICE MODULE│        │
│  │  "EKS with   │ │  "RDS with   │ │  "VPC with   │        │
│  │   all the    │ │   backups    │ │   standard   │        │
│  │   fixings"   │ │   & replicas"│ │   layout"    │        │
│  └──────┬───────┘ └──────┬───────┘ └──────┬───────┘        │
│         │                │                │                  │
│         v                v                v                  │
│  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐        │
│  │  RESOURCE    │ │  RESOURCE    │ │  RESOURCE    │        │
│  │  MODULES     │ │  MODULES     │ │  MODULES     │        │
│  │  (Thin       │ │  (Thin       │ │  (Thin       │        │
│  │   wrappers)  │ │   wrappers)  │ │   wrappers)  │        │
│  └──────────────┘ └──────────────┘ └──────────────┘        │
└─────────────────────────────────────────────────────────────┘
```

**Resource modules** wrap a single resource or a tightly coupled pair. They add validation, defaults, and tagging. Think of them as your company's opinion about how a resource should be configured.

```hcl
# modules/security-group/main.tf
resource "aws_security_group" "this" {
  name_prefix = "${var.name}-"
  vpc_id      = var.vpc_id
  description = var.description

  tags = merge(var.tags, {
    Name      = var.name
    ManagedBy = "terraform"
  })

  lifecycle {
    create_before_destroy = true
  }
}
```

**Service modules** combine multiple resource modules into a logical service. An EKS service module creates the cluster, node groups, OIDC provider, and essential add-ons.

**Composition modules** are your environment definitions. They wire service modules together. This is where `main.tf` in your environment directory lives.

### Module Interface Design

The interface of a module (its variables and outputs) is more important than its implementation. A well-designed interface lets you change the internals without breaking callers.

**Rule 1: Required variables should be few.** If your module has 30 required variables, it is too hard to use. Provide sensible defaults.

```hcl
# BAD: Too many required variables
variable "vpc_cidr" {}
variable "public_subnet_cidrs" {}
variable "private_subnet_cidrs" {}
variable "enable_nat_gateway" {}
variable "single_nat_gateway" {}
variable "enable_dns_support" {}
variable "enable_dns_hostnames" {}

# GOOD: Sensible defaults, few required
variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  # No default -- this MUST be specified
}

variable "environment" {
  description = "Environment name (dev, staging, production)"
  type        = string
}

variable "enable_nat_gateway" {
  description = "Whether to create NAT gateways for private subnets"
  type        = bool
  default     = true
}

variable "single_nat_gateway" {
  description = "Use a single NAT gateway instead of one per AZ (cheaper, less resilient)"
  type        = bool
  default     = false
}
```

**Rule 2: Outputs should be generous.** You never know what a consumer will need. Output everything that could be useful.

```hcl
# modules/vpc/outputs.tf
output "vpc_id" {
  description = "The ID of the VPC"
  value       = aws_vpc.main.id
}

output "vpc_cidr" {
  description = "The CIDR block of the VPC"
  value       = aws_vpc.main.cidr_block
}

output "private_subnet_ids" {
  description = "List of private subnet IDs"
  value       = aws_subnet.private[*].id
}

output "private_subnet_cidrs" {
  description = "List of private subnet CIDR blocks"
  value       = aws_subnet.private[*].cidr_block
}

output "public_subnet_ids" {
  description = "List of public subnet IDs"
  value       = aws_subnet.public[*].id
}

output "nat_gateway_ips" {
  description = "List of NAT Gateway public IPs"
  value       = aws_eip.nat[*].public_ip
}
```

**Rule 3: Use validation blocks to catch mistakes early.**

```hcl
variable "environment" {
  description = "Environment name"
  type        = string

  validation {
    condition     = contains(["dev", "staging", "production"], var.environment)
    error_message = "Environment must be dev, staging, or production."
  }
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr must be a valid CIDR block."
  }
}
```

### Module Versioning

For modules in the same repo, you use relative paths:

```hcl
module "vpc" {
  source = "../../modules/vpc"
}
```

For shared modules across repos, use versioned references:

```hcl
module "vpc" {
  source  = "git::https://github.com/mycompany/terraform-modules.git//vpc?ref=v2.1.0"
}
```

**Never use `ref=main`** for production. This means any push to main changes your infrastructure without review.

> **What breaks in production**: Team A updates a shared module and pushes to main. Team B runs `terraform plan` and gets unexpected changes because their module source pointed to `ref=main`. The plan shows 15 resources changing. Team B does not understand why. They apply anyway because they trust the module team. A subtle breaking change in the module's security group rules opens port 22 to 0.0.0.0/0. Use version tags. Always.

---

## 5. Multi-Environment Strategies

### Strategy 1: Workspaces (Simple but Limited)

Terraform workspaces let you use the same code with different state files.

```bash
terraform workspace new staging
terraform workspace new production
terraform workspace select staging
terraform apply -var-file="staging.tfvars"
```

```hcl
# Using workspace name in code
resource "aws_instance" "web" {
  instance_type = terraform.workspace == "production" ? "m5.xlarge" : "t3.medium"

  tags = {
    Environment = terraform.workspace
  }
}
```

**When workspaces work:**

- Small teams (1-3 people)
- Environments that are nearly identical
- Simple infrastructure (under 50 resources)

**When workspaces fail:**

- Different environments need different resources (prod has a read replica, dev does not)
- You need different AWS accounts per environment
- You need different backend configurations per environment
- Multiple people need to work on different environments simultaneously

The fundamental problem with workspaces is that they share the same code. In practice, environments diverge. Production gets monitoring that dev does not need. Staging gets synthetic load testing that production must not have. You end up with conditionals everywhere:

```hcl
# This is where workspaces lead you
resource "aws_rds_cluster" "replica" {
  count = terraform.workspace == "production" ? 1 : 0
  # ...
}

resource "aws_cloudwatch_metric_alarm" "cpu" {
  count = terraform.workspace == "production" ? 1 : 0
  # ...
}

# Three months later, your code is 40% conditionals
```

### Strategy 2: Directory Per Environment (Recommended)

Each environment gets its own directory. Shared logic lives in modules.

```hcl
# environments/dev/main.tf
module "vpc" {
  source = "../../modules/vpc"

  vpc_cidr    = "10.0.0.0/16"
  environment = "dev"

  # Dev: single NAT gateway to save money
  single_nat_gateway = true
}

module "eks" {
  source = "../../modules/eks"

  cluster_version = "1.28"
  environment     = "dev"

  # Dev: smaller, fewer nodes
  node_instance_types = ["t3.medium"]
  desired_capacity    = 2
  max_capacity        = 4
}
```

```hcl
# environments/production/main.tf
module "vpc" {
  source = "../../modules/vpc"

  vpc_cidr    = "10.1.0.0/16"
  environment = "production"

  # Prod: NAT gateway per AZ for resilience
  single_nat_gateway = false
}

module "eks" {
  source = "../../modules/eks"

  cluster_version = "1.28"
  environment     = "production"

  # Prod: larger, more nodes, GPU nodes for ML
  node_instance_types = ["m5.xlarge"]
  desired_capacity    = 10
  max_capacity        = 50
}

# Prod-only: read replica
module "rds_replica" {
  source = "../../modules/rds-replica"

  primary_cluster_id = module.rds.cluster_id
}
```

This is explicit, readable, and each environment is independently deployable.

### Strategy 3: Variable Files (Middle Ground)

Same structure but use `.tfvars` files to parameterize environments:

```
environments/
├── main.tf
├── variables.tf
├── dev.tfvars
├── staging.tfvars
└── production.tfvars
```

```bash
terraform plan -var-file="production.tfvars"
```

This works when environments are truly identical except for sizing. In practice, they rarely are.

---

## 6. Monorepo vs Multi-Repo

This is one of the most debated decisions in Terraform project design.

### Monorepo: Everything in One Repository

```
infrastructure/
├── modules/
│   ├── vpc/
│   ├── eks/
│   ├── rds/
│   └── monitoring/
├── environments/
│   ├── dev/
│   ├── staging/
│   └── production/
├── global/
│   ├── iam/
│   └── dns/
└── scripts/
    ├── apply.sh
    └── plan.sh
```

**Advantages:**

- Single source of truth. Everything is here.
- Easy to refactor. Rename a module variable and update all callers in one PR.
- Consistent tooling. One CI/CD pipeline for everything.
- Cross-cutting changes are atomic. Update a module and all environments in one PR.

**Disadvantages:**

- Blast radius of a bad merge is the entire infrastructure.
- CI/CD must be smart about which environments to plan/apply based on changed files.
- Repository grows large. `git clone` gets slow.
- Access control is coarse. Everyone can see (and potentially change) everything.

### Multi-Repo: Separate Repositories Per Concern

```
# Repo: terraform-modules
modules/
├── vpc/
├── eks/
├── rds/
└── monitoring/

# Repo: terraform-production
environments/production/
├── networking/
├── compute/
└── database/

# Repo: terraform-staging
environments/staging/
├── networking/
├── compute/
└── database/

# Repo: terraform-global
global/
├── iam/
└── dns/
```

**Advantages:**

- Fine-grained access control. Only the platform team can push to `terraform-production`.
- Clear ownership. Each repo has a CODEOWNERS file.
- Module versioning is forced. Consumers must pin to a version tag.
- Smaller repositories are faster to clone and easier to navigate.

**Disadvantages:**

- Cross-cutting changes require multiple PRs across repos.
- Module updates are a two-step process: update the module repo, then update consumers.
- More CI/CD pipelines to maintain.
- Risk of version skew between environments.

### The Hybrid Approach (What Most Mature Teams Use)

```
# Repo 1: terraform-modules (shared library)
# Repo 2: terraform-infrastructure (all environments)
```

Modules are in their own repo with semantic versioning. Environments are in a single repo that consumes the module repo. This gives you:

- Module versioning and access control via the module repo
- Atomic environment changes via the infrastructure repo
- A manageable number of repositories (2 instead of N)

---

## 7. State File Organization

State files are the heart of Terraform. How you organize them determines your blast radius, your team's parallelism, and your recovery options.

### The Golden Rule

**One state file per independently deployable unit.**

What is an "independently deployable unit"? It is a set of resources that:

1. Change together
2. Are owned by the same team
3. Have the same lifecycle (created and destroyed together)

### State File Granularity Spectrum

```
COARSE                                                    FINE
  |                                                         |
  |  One state     One state     One state per    One state |
  |  for           per           component per    per       |
  |  everything    environment   environment      resource  |
  |                                                         |
  |  Dangerous     Good start    Best for most    Overkill  |
  |  in prod       for small     teams                      |
  |                teams                                    |
```

### Backend Configuration

Every state file needs a backend. For AWS, S3 + DynamoDB is the standard:

```hcl
# environments/production/networking/backend.tf
terraform {
  backend "s3" {
    bucket         = "mycompany-terraform-state"
    key            = "production/networking/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-locks"
  }
}
```

### State File Naming Convention

Use a consistent key pattern:

```
{environment}/{component}/terraform.tfstate
```

Examples:
```
production/networking/terraform.tfstate
production/compute/terraform.tfstate
production/database/terraform.tfstate
staging/networking/terraform.tfstate
global/iam/terraform.tfstate
global/dns/terraform.tfstate
```

### Cross-State References

When one component needs data from another, use `terraform_remote_state`:

```hcl
data "terraform_remote_state" "networking" {
  backend = "s3"
  config = {
    bucket = "mycompany-terraform-state"
    key    = "production/networking/terraform.tfstate"
    region = "us-east-1"
  }
}

resource "aws_eks_cluster" "main" {
  vpc_config {
    subnet_ids = data.terraform_remote_state.networking.outputs.private_subnet_ids
  }
}
```

**Alternative: Use SSM Parameter Store or AWS Secrets Manager** as a data exchange layer. This decouples state files completely:

```hcl
# In the networking component: write to SSM
resource "aws_ssm_parameter" "vpc_id" {
  name  = "/infrastructure/production/vpc_id"
  type  = "String"
  value = aws_vpc.main.id
}

# In the compute component: read from SSM
data "aws_ssm_parameter" "vpc_id" {
  name = "/infrastructure/production/vpc_id"
}
```

This approach is more resilient -- the compute component does not need access to the networking state file.

> **What breaks in production**: You reorganize your state files and use `terraform state mv` to move resources between state files. You forget one resource. The next `terraform apply` on the old state file tries to destroy it (it is in the state but not in the code). The next apply on the new state file tries to create it (it is in the code but not in the state). You get a conflict error from AWS. Always run `terraform plan` on both the source and destination state files after moving resources, and verify the plans are clean before applying either.

---

## 8. The DRY Principle in Terraform

DRY (Don't Repeat Yourself) in Terraform is different from DRY in application code. In application code, duplication is almost always bad. In Terraform, some duplication is not only acceptable -- it is preferable.

### Where DRY Is Good

**Module reuse across environments.** This is the primary mechanism. Your VPC module is written once and called from each environment with different parameters.

**Shared variable definitions.** Using `locals` to compute values from inputs:

```hcl
locals {
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
    Team        = var.team_name
  }

  name_prefix = "${var.project_name}-${var.environment}"
}
```

**Shared backend configuration.** With Terragrunt, the backend configuration is defined once in the root `terragrunt.hcl` and inherited by all children.

### Where DRY Is Harmful

**Over-abstracting modules.** When you try to make a module handle every possible use case, you end up with a module that is harder to use than the raw resources.

```hcl
# BAD: Over-abstracted module
module "resource" {
  source = "../../modules/generic-resource"

  resource_type = "aws_instance"
  properties = {
    ami           = "ami-12345"
    instance_type = "t3.medium"
  }
  nested_blocks = [
    {
      type = "ebs_block_device"
      properties = {
        volume_size = 100
      }
    }
  ]
}

# GOOD: Just use the resource
resource "aws_instance" "web" {
  ami           = "ami-12345"
  instance_type = "t3.medium"

  ebs_block_device {
    volume_size = 100
  }
}
```

**Sharing too much between environments.** When dev and production share the exact same code and differ only in variables, you lose the ability to test infrastructure changes in dev before applying to production. Sometimes having a slightly different `main.tf` in dev is the right call.

### The Rule of Three

Before creating a module, wait until you have written the same pattern three times. The first time, you do not know the right abstraction. The second time, you start to see the pattern. The third time, you know what to abstract.

---

## 9. Anti-Patterns That Will Haunt You

### Anti-Pattern 1: The God Module

A single module that creates your entire infrastructure.

```hcl
# DO NOT DO THIS
module "everything" {
  source = "../../modules/infrastructure"

  vpc_cidr              = "10.0.0.0/16"
  eks_cluster_version   = "1.28"
  rds_instance_class    = "db.r5.xlarge"
  redis_node_type       = "cache.r5.large"
  # ... 200 more variables
}
```

This is the flat file anti-pattern wrapped in a module. Same problems, different syntax.

### Anti-Pattern 2: Circular Dependencies Between State Files

```
State A reads from State B
State B reads from State A
```

You cannot apply either one first. You are stuck. Design your state file dependencies as a DAG (directed acyclic graph), just like Terraform designs resource dependencies.

```
┌──────────┐
│  Global  │  (IAM, DNS)
│  State   │
└────┬─────┘
     │
     v
┌──────────┐
│Networking│  (VPC, subnets)
│  State   │
└────┬─────┘
     │
  ┌──┴───┐
  v      v
┌────┐ ┌────┐
│EKS │ │RDS │
│State│ │State│
└──┬─┘ └────┘
   v
┌────────┐
│Helm    │
│Releases│
│State   │
└────────┘
```

### Anti-Pattern 3: Using `count` for Things That Have Identity

```hcl
# BAD: If you remove a subnet from the middle, everything shifts
resource "aws_subnet" "private" {
  count      = length(var.availability_zones)
  cidr_block = var.subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]
}

# GOOD: Each subnet has a stable identity
resource "aws_subnet" "private" {
  for_each          = toset(var.availability_zones)
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, index(var.availability_zones, each.value))
  availability_zone = each.value
}
```

### Anti-Pattern 4: Secrets in Terraform State

```hcl
# This password is now stored in plain text in the state file
resource "aws_db_instance" "main" {
  master_password = var.db_password
}
```

Even with encrypted state files, anyone with state access can read the password. Use AWS Secrets Manager and reference the secret's ARN instead.

### Anti-Pattern 5: Not Using `.terraform.lock.hcl`

The lock file pins your provider versions. Without it, `terraform init` might download a newer provider version that has breaking changes. Always commit `.terraform.lock.hcl`.

```bash
# Generate or update the lock file for all platforms
terraform providers lock \
  -platform=linux_amd64 \
  -platform=darwin_amd64 \
  -platform=darwin_arm64
```

### Anti-Pattern 6: Hardcoded Values Everywhere

```hcl
# BAD
resource "aws_instance" "web" {
  ami           = "ami-0c55b159cbfafe1f0"
  instance_type = "t3.medium"
  subnet_id     = "subnet-0bb1c79de3EXAMPLE"
}

# GOOD
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

resource "aws_instance" "web" {
  ami           = data.aws_ami.amazon_linux.id
  instance_type = var.instance_type
  subnet_id     = module.vpc.private_subnet_ids[0]
}
```

---

## 10. Real-World Examples

### Example 1: Startup (3 Engineers, 1 AWS Account)

```
infrastructure/
├── modules/
│   ├── vpc/
│   └── ecs/          # Using ECS, not EKS (simpler)
├── environments/
│   ├── dev/
│   │   ├── main.tf
│   │   └── backend.tf
│   └── production/
│       ├── main.tf
│       └── backend.tf
└── global/
    └── iam/
```

- Two environments, three state files
- No Terragrunt (not needed yet)
- No component-level splitting (under 50 resources per env)
- Modules in the same repo (no need for separate module repo)

### Example 2: Mid-Stage Company (15 Engineers, 3 AWS Accounts)

```
# Repo: terraform-modules
modules/
├── vpc/
├── eks/
├── rds/
├── monitoring/
└── iam-role/

# Repo: terraform-infrastructure
environments/
├── dev/        # AWS Account: 111111111111
│   ├── networking/
│   ├── compute/
│   └── database/
├── staging/    # AWS Account: 222222222222
│   ├── networking/
│   ├── compute/
│   └── database/
└── production/ # AWS Account: 333333333333
    ├── networking/
    ├── compute/
    ├── database/
    └── monitoring/
```

- Separate AWS accounts per environment
- Module repo with semantic versioning
- Component-level state file splitting in production
- CI/CD pipeline with plan-on-PR, apply-on-merge

### Example 3: Enterprise (100+ Engineers, 20+ AWS Accounts)

```
# Repo: terraform-modules (platform team owns)
# Repo: terraform-platform (platform team owns)
#   - Shared VPCs, transit gateways, centralized logging
# Repo: terraform-team-payments (payments team owns)
#   - Their EKS workloads, databases
# Repo: terraform-team-auth (auth team owns)
#   - Their services
# Terragrunt used in all repos
# Atlantis for plan/apply automation
# OPA/Sentinel for policy enforcement
```

At this scale, you need:
- Policy-as-code (OPA or Sentinel) to enforce standards
- Service catalog modules that teams consume
- Automated drift detection
- FinOps integration for cost tracking

---

## 11. Test Yourself

These questions test your understanding of Terraform project structure decisions. Try to answer them before looking at the solutions.

**Question 1**: You have a Terraform project with 300 resources in a single state file. `terraform plan` takes 12 minutes. What is the most effective way to reduce plan time?

**Answer**: Split the state file by component (networking, compute, database, monitoring). Each component will have fewer resources to refresh, reducing plan time proportionally. You will use `terraform_remote_state` or SSM parameters to share data between components.

**Question 2**: Your team uses Terraform workspaces for dev, staging, and production. Production needs a read replica for the database, but dev and staging do not. How would you handle this, and what are the trade-offs?

**Answer**: You could use `count = terraform.workspace == "production" ? 1 : 0` on the replica resource. However, this is a sign that workspaces are the wrong tool. The better approach is to switch to directory-per-environment and add the replica module only in the production directory. The trade-off is more files to maintain, but clearer intent and no conditional logic.

**Question 3**: Two state files have a circular dependency -- State A needs an output from State B, and State B needs an output from State A. How do you break the cycle?

**Answer**: Extract the shared resource into a third state file that both A and B depend on. Alternatively, use SSM Parameter Store as an intermediary -- one state writes, the other reads -- and break the Terraform-level dependency. Restructure so dependencies flow in one direction.

**Question 4**: You are using `source = "git::https://github.com/mycompany/modules.git//vpc?ref=main"` for your VPC module. What is the risk?

**Answer**: Any push to the main branch of the modules repo will change your infrastructure on the next `terraform init` or `terraform plan`. Someone could introduce a breaking change or a security misconfiguration, and it would be pulled in automatically. Always use a version tag like `ref=v2.1.0`.

**Question 5**: Your module has 45 input variables, 30 of which are required (no default). What is wrong, and how would you fix it?

**Answer**: The module is trying to do too much and is too hard to use. Fix it by: (1) Adding sensible defaults to most variables so only 3-5 are truly required. (2) Splitting the module into smaller, focused modules. (3) Using an opinionated "service module" pattern where the module makes decisions for you and exposes only the knobs that callers actually need to turn.

**Question 6**: You have a monorepo with environments for dev, staging, and production. A junior engineer opens a PR that changes a module used by all three environments. What CI/CD safeguards should be in place?

**Answer**: The CI pipeline should: (1) Run `terraform plan` for all three environments and post the plan output on the PR. (2) Require approval from a senior engineer or the platform team. (3) Apply to dev first, then staging, then production -- with manual approval gates between each. (4) Run `terraform validate` and a linter (tflint) on every PR. (5) Optionally run policy checks (OPA/Sentinel) to catch security violations.

**Question 7**: You are moving from a flat structure (one directory with everything) to a component-based structure. You need to move resources between state files without destroying and recreating them. What commands do you use, and what is the risk?

**Answer**: Use `terraform state mv` to move resources from one state to another. The commands are: `terraform state mv -state=old.tfstate -state-out=new.tfstate aws_vpc.main aws_vpc.main`. The risk is forgetting a resource -- the old state will try to destroy it, and the new state will try to create it. Always run `terraform plan` on both state files after the move and verify clean plans before applying.

**Question 8**: Your team argues about monorepo vs multi-repo for Terraform. The team has 8 engineers, 3 AWS accounts, and about 200 resources total. What do you recommend and why?

**Answer**: Monorepo. With 8 engineers and 200 resources, the overhead of multiple repos is not justified. A monorepo gives you atomic cross-environment changes, simpler CI/CD, and easier refactoring. Separate the modules directory from the environments directory, and use CODEOWNERS to restrict who can approve changes to production. Consider multi-repo only when you have distinct teams that need independent release cycles.

**Question 9**: You use `terraform_remote_state` to read the VPC ID from the networking state file in your compute state file. The networking team removes the `vpc_id` output. What happens, and how do you prevent this?

**Answer**: The next `terraform plan` on the compute state file will fail with an error saying the output does not exist. To prevent this: (1) Treat outputs as a public API contract -- never remove them without checking consumers. (2) Use a CI check that scans for removed outputs and flags them. (3) Consider using SSM Parameter Store as an intermediary, which decouples the state files entirely.

**Question 10**: You are designing a Terraform project for a new microservices platform. There will be 10 microservices, each with its own database and message queue. Each service is owned by a different team. How would you structure the repositories and state files?

**Answer**: Use a shared modules repo for common patterns (database module, message queue module, service module). Give each team their own directory (or repo, depending on team independence needs) for their service's infrastructure. Each service gets its own state file. Shared infrastructure (VPC, EKS cluster, monitoring) lives in a platform repo owned by the platform team. The platform team provides a "service module" that teams consume to deploy their service onto the shared EKS cluster. This gives teams independence while maintaining consistency.

---

> **Key Takeaway**: The right project structure depends on your team size, the number of resources, and how much independence teams need. Start with the simplest structure that gives you separate state files per environment, and evolve toward component-based splitting as your infrastructure grows. Do not over-engineer on day one -- but do not ignore structure either.
