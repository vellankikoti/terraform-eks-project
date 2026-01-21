# 01 - Terraform Fundamentals: From Zero to Mental Clarity

> **Goal**: Understand Terraform so deeply that you can explain it to a 10-year-old AND impress a Principal Engineer.

---

## Table of Contents

1. [What Terraform Really Is](#1-what-terraform-really-is)
2. [The Core Mental Model](#2-the-core-mental-model)
3. [Declarative vs Imperative](#3-declarative-vs-imperative)
4. [Why Terraform Beats Everything Else](#4-why-terraform-beats-everything-else)
5. [The Terraform Workflow](#5-the-terraform-workflow)
6. [Providers, Resources, Data Sources](#6-providers-resources-data-sources)
7. [State: The Bank Ledger of Infrastructure](#7-state-the-bank-ledger-of-infrastructure)
8. [Why State Is Dangerous](#8-why-state-is-dangerous)

---

## 1. What Terraform Really Is

### The Marketing Version (Ignore This)

"Terraform is infrastructure as code that lets you build, change, and version infrastructure safely and efficiently."

### The Real Version (This Matters)

**Terraform is a tool that:**

1. **Reads your "desired state"** written in code
2. **Compares it to "current state"** of real infrastructure
3. **Calculates the difference** (the "delta")
4. **Makes API calls** to cloud providers to fix the delta
5. **Records what it did** in a state file

That's it. Everything else is details.

### Explain Like I'm 10 🧒

Imagine you have a **Lego city** and you want it to look a specific way.

**Without Terraform:**
- You remember what your city looks like in your head
- You manually add/remove pieces
- If your friend changes it, you might not notice
- If you knock it over, you don't remember exactly how it was

**With Terraform:**
- You write down instructions: "3 red houses, 2 blue cars, 1 yellow tree"
- Terraform looks at your actual Lego city
- It says: "You have 2 red houses but need 3, adding 1 red house"
- It writes down what the city looks like NOW in a notebook (state file)

Next day:
- You change your instructions: "4 red houses" instead of 3
- Terraform reads its notebook (state), sees you had 3
- It says: "Need to add 1 more red house"
- Builds it and updates the notebook

---

## 2. The Core Mental Model

### The Three "States" (Don't Confuse These)

```
┌─────────────────────┐
│  DESIRED STATE      │  ← What you wrote in Terraform code
│  (*.tf files)       │    "I want 3 EC2 instances"
└──────────┬──────────┘
           │
           ↓  terraform plan compares these
           │
┌──────────┴──────────┐
│  RECORDED STATE     │  ← What Terraform thinks exists
│  (terraform.tfstate)│    "Last time I checked, there were 2 EC2 instances"
└──────────┬──────────┘
           │
           ↓  Terraform makes API calls to sync
           │
┌──────────┴──────────┐
│  ACTUAL STATE       │  ← What actually exists in AWS
│  (Real AWS Infra)   │    "There are 2 EC2 instances running right now"
└─────────────────────┘
```

### The Critical Insight ⚠️

**Most production incidents happen when these three states diverge.**

Example disaster scenario:
1. Terraform state says: "3 EC2 instances"
2. Someone manually deletes one in AWS console
3. Actual state: 2 EC2 instances
4. Terraform doesn't know about the deletion
5. Next `terraform apply` might do unexpected things

**Golden Rule**: Never manually change infrastructure that Terraform manages.

---

## 3. Declarative vs Imperative

### The Difference (Explained Clearly)

#### Imperative (Step-by-Step Instructions)

```bash
# Shell script approach
aws ec2 run-instances --image-id ami-12345 --count 1 --instance-type t3.medium
aws ec2 create-tags --resources i-xxx --tags Key=Name,Value=web-server
aws ec2 associate-address --instance-id i-xxx --allocation-id eipalloc-yyy

# If you run this twice, you get 2 instances (BAD!)
# If step 2 fails, you're in a weird state
# If someone deletes something, script doesn't know
```

You tell the computer **HOW** to do something, step by step.

#### Declarative (Desired End State)

```hcl
# Terraform approach
resource "aws_instance" "web" {
  ami           = "ami-12345"
  instance_type = "t3.medium"

  tags = {
    Name = "web-server"
  }
}

resource "aws_eip" "web" {
  instance = aws_instance.web.id
}

# Run this 100 times = still just 1 instance
# Terraform figures out the steps
# Terraform knows current state
```

You tell the computer **WHAT** you want, and it figures out how to get there.

### Real-World Analogy 🏠

#### Imperative (Building a House)

"Step 1: Pour foundation
Step 2: Build walls
Step 3: Add roof
Step 4: Install windows"

Problem: What if walls already exist? Script doesn't know, might try to build walls again.

#### Declarative (Building a House)

"I want a house with:
- Foundation: concrete
- Walls: 4 walls, brick
- Roof: shingles
- Windows: 8 windows"

Terraform looks at the empty lot and says: "I need to build all of this."
Next time you run it, Terraform says: "House matches the description, nothing to do."

You want to add 2 more windows:
- Terraform sees: "Current house has 8 windows, desired is 10"
- Terraform only adds 2 windows (doesn't rebuild the whole house)

### Why Declarative Wins

1. **Idempotent**: Run it 100 times = same result
2. **Self-healing**: If someone breaks something, next apply fixes it
3. **Drift detection**: Terraform knows what changed outside of its control
4. **Readable**: Code describes end state, not steps

---

## 4. Why Terraform Beats Everything Else

### vs. Manual Changes (AWS Console)

| Manual Console | Terraform |
|----------------|-----------|
| No history | Git history of all changes |
| No review process | Code review before apply |
| No automation | Fully automated |
| Error-prone | Validated before execution |
| Doesn't scale | Manages thousands of resources |
| "Who changed this?" | `git blame` shows who |

### vs. Shell Scripts

| Shell Scripts | Terraform |
|---------------|-----------|
| Imperative (step-by-step) | Declarative (desired state) |
| No state tracking | State file tracks everything |
| Run twice = duplicate resources | Idempotent |
| No dry-run | `terraform plan` shows preview |
| Complex error handling | Built-in dependency resolution |

### vs. AWS CloudFormation

| CloudFormation | Terraform |
|----------------|-----------|
| AWS only | Multi-cloud (AWS, GCP, Azure, etc.) |
| JSON/YAML (verbose) | HCL (concise, readable) |
| Slower execution | Faster parallel execution |
| Limited looping/conditionals | Powerful language features |
| AWS-specific naming | Consistent naming across clouds |

**Real Talk**: CloudFormation is fine for AWS-only shops. But Terraform's ecosystem, speed, and multi-cloud support make it the industry standard.

### vs. Ansible

**Ansible** = Configuration management (set up servers, install software)
**Terraform** = Infrastructure provisioning (create servers, networks, databases)

They solve different problems. Many teams use **both**:
- Terraform creates the EC2 instance
- Ansible installs and configures the application

---

## 5. The Terraform Workflow

### The Four Sacred Commands

```
terraform init
    ↓
terraform plan
    ↓
terraform apply
    ↓
terraform destroy  (when you're done)
```

Let's break down each one.

---

### `terraform init`

**What it does**: Downloads provider plugins and sets up the backend.

```bash
$ terraform init

Initializing provider plugins...
- Downloading hashicorp/aws v5.31.0...

Terraform has been successfully initialized!
```

**Under the Hood:**

1. Reads `provider` blocks in your `.tf` files
2. Downloads provider binaries to `.terraform/` directory
3. Sets up remote state backend (if configured)
4. Creates a `.terraform.lock.hcl` file (locks provider versions)

**When to run:**
- First time in a new Terraform directory
- After adding a new provider
- After changing backend configuration
- When cloning a repo

**Mental Model**: Like `npm install` or `pip install` - sets up dependencies.

---

### `terraform plan`

**What it does**: Shows you what will change **before** changing it.

```bash
$ terraform plan

Terraform will perform the following actions:

  # aws_instance.web will be created
  + resource "aws_instance" "web" {
      + ami           = "ami-12345"
      + instance_type = "t3.medium"
      ...
    }

Plan: 1 to add, 0 to change, 0 to destroy.
```

**Under the Hood:**

1. Reads your `.tf` files (desired state)
2. Reads `terraform.tfstate` (recorded state)
3. Calls AWS APIs to get actual current state
4. Builds a dependency graph
5. Calculates the diff
6. Shows you the execution plan

**Output Symbols:**

- `+` = create
- `-` = destroy
- `~` = update in-place
- `-/+` = destroy and recreate (replacement)
- `<=` = read (data source)

**Mental Model**: Like `git diff` before `git commit`. Shows what will change.

**Pro Tip**: Always run `plan` before `apply`. Always. No exceptions.

---

### `terraform apply`

**What it does**: Executes the plan and makes changes to real infrastructure.

```bash
$ terraform apply

# Shows the plan again
# Asks for confirmation

Do you want to perform these actions?
  Terraform will perform the actions described above.
  Only 'yes' will be accepted to approve.

  Enter a value: yes

aws_instance.web: Creating...
aws_instance.web: Creation complete after 45s

Apply complete! Resources: 1 added, 0 changed, 0 destroyed.
```

**Under the Hood:**

1. Runs `terraform plan` again (to catch last-second changes)
2. Waits for your confirmation (`yes`)
3. Executes the plan in the correct order (respecting dependencies)
4. Makes API calls to AWS (or other providers)
5. Updates `terraform.tfstate` with new state
6. Outputs any defined outputs

**Auto-Approve (Dangerous!):**

```bash
terraform apply -auto-approve  # Skips confirmation - use in CI/CD only
```

**Mental Model**: Like `git push` - makes your changes real.

---

### `terraform destroy`

**What it does**: Deletes all infrastructure managed by this Terraform configuration.

```bash
$ terraform destroy

Terraform will destroy all your infrastructure!
  - aws_instance.web
  - aws_eip.web
  - aws_security_group.web

Do you really want to destroy all resources?
  Enter a value: yes

Destroying... (this can take several minutes)

Destroy complete! Resources: 3 destroyed.
```

**Under the Hood:**

1. Reads state file to see what exists
2. Creates a plan to destroy everything
3. Destroys resources in reverse dependency order (opposite of creation)

**⚠️ WARNING**: This is irreversible. There is no "undo."

**Production Safety**:
```bash
# Prevent accidental destruction
terraform apply -destroy  # Alternative syntax, same danger
```

In production, you might add this to your code:
```hcl
lifecycle {
  prevent_destroy = true  # Terraform will refuse to destroy this resource
}
```

---

## 6. Providers, Resources, Data Sources

### Providers (The API Clients)

A **provider** is a plugin that knows how to talk to a specific service.

```hcl
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}
```

**What's happening:**
- `required_providers`: Declares which providers you need
- `provider` block: Configures the provider (region, credentials, etc.)

**Popular Providers:**
- `aws` - Amazon Web Services
- `azurerm` - Microsoft Azure
- `google` - Google Cloud Platform
- `kubernetes` - Kubernetes clusters
- `helm` - Helm charts
- `datadog` - Datadog monitoring
- `github` - GitHub repos
- 1000+ more on the Terraform Registry

**Mental Model**: Providers are like npm packages - they give Terraform the ability to manage specific services.

---

### Resources (Things You Create)

A **resource** is something you want to exist.

```hcl
resource "aws_instance" "web" {
  ami           = "ami-0c55b159cbfafe1f0"
  instance_type = "t3.medium"

  tags = {
    Name = "web-server"
  }
}
```

**Syntax:**
```hcl
resource "TYPE" "NAME" {
  argument = value
  ...
}
```

- `TYPE`: The resource type from the provider (`aws_instance`, `aws_s3_bucket`, etc.)
- `NAME`: A local name you choose (used to reference this resource)

**Referencing Resources:**

```hcl
resource "aws_instance" "web" {
  ami           = "ami-12345"
  instance_type = "t3.medium"
}

resource "aws_eip" "web_ip" {
  instance = aws_instance.web.id  # ← Reference the instance above
}
```

**Mental Model**: Resources are like function calls that create things.

---

### Data Sources (Things You Read)

A **data source** is information you want to look up (not create).

```hcl
# Look up the latest Amazon Linux 2 AMI
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

# Use it in a resource
resource "aws_instance" "web" {
  ami           = data.aws_ami.amazon_linux.id  # ← Use the looked-up AMI
  instance_type = "t3.medium"
}
```

**Syntax:**
```hcl
data "TYPE" "NAME" {
  # Query parameters
}
```

**Common Use Cases:**

1. **Look up AMIs** (so you don't hardcode AMI IDs)
2. **Look up existing VPCs** (when you don't manage the VPC with Terraform)
3. **Look up availability zones** (to make code region-agnostic)
4. **Look up current AWS account ID** (for IAM policies)

**Mental Model**: Data sources are like API queries - you're reading information, not creating it.

---

### The Difference (Resource vs Data Source)

| Resource | Data Source |
|----------|-------------|
| **Creates** infrastructure | **Reads** existing infrastructure |
| Terraform manages its lifecycle | Terraform just queries it |
| Appears in state file as managed | Appears in state file as read-only |
| Example: `resource "aws_instance"` | Example: `data "aws_ami"` |

---

## 7. State: The Bank Ledger of Infrastructure

### What Is the State File?

The **state file** (`terraform.tfstate`) is a JSON file that records:

1. What resources Terraform created
2. The attributes of those resources (IDs, IPs, ARNs, etc.)
3. Metadata (dependencies, timestamps)

**Example state file snippet:**

```json
{
  "version": 4,
  "terraform_version": "1.6.0",
  "resources": [
    {
      "type": "aws_instance",
      "name": "web",
      "provider": "provider[\"registry.terraform.io/hashicorp/aws\"]",
      "instances": [
        {
          "attributes": {
            "id": "i-0123456789abcdef",
            "ami": "ami-12345",
            "instance_type": "t3.medium",
            "public_ip": "54.123.45.67",
            ...
          }
        }
      ]
    }
  ]
}
```

### Why State Exists

Without state, Terraform would have to query your cloud provider **every time** to figure out:
- What resources exist
- What Terraform created vs what existed before
- Resource dependencies

State makes Terraform fast and reliable.

### The Bank Ledger Analogy 🏦

**State file = Bank ledger**

When you make a bank transaction:
- The bank writes down: "Account 12345 now has $500"
- Next transaction: Bank reads the ledger to know your balance
- If the ledger is wrong, bad things happen

**With Terraform:**
- You create an EC2 instance
- Terraform writes down: "Instance i-12345 exists in us-east-1"
- Next apply: Terraform reads state to know what exists
- If state is wrong, Terraform might create duplicates or delete things

### Local vs Remote State

**Local State** (Default)

```
terraform.tfstate  # File on your laptop
```

**Problems:**
- Not shared with team members
- No locking (two people can apply simultaneously → corruption)
- Lost if laptop dies
- Contains sensitive data (passwords, keys)

**Remote State** (Production Standard)

```hcl
terraform {
  backend "s3" {
    bucket         = "my-terraform-state"
    key            = "prod/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-locks"  # For locking
    encrypt        = true
  }
}
```

**Benefits:**
- Shared with team
- State locking (prevents concurrent applies)
- Encrypted at rest
- Versioned (can roll back if needed)
- Backed up

**Golden Rule**: Always use remote state for anything beyond local testing.

---

## 8. Why State Is Dangerous

### Danger #1: State Corruption

**Scenario**: Two engineers run `terraform apply` at the same time.

```
Engineer A: Reads state → Plans to add resource X → Applies
Engineer B: Reads state (same time) → Plans to add resource Y → Applies
Result: State file is corrupted (one person's changes overwrite the other's)
```

**Solution**: State locking with DynamoDB (or equivalent).

When using S3 + DynamoDB backend:
```
Engineer A: Acquires lock → Applies → Releases lock
Engineer B: Tries to acquire lock → BLOCKED until A is done → Then applies
```

---

### Danger #2: State Deletion

**Someone accidentally runs:**
```bash
rm terraform.tfstate
```

**What happens:**
- Terraform thinks nothing exists
- Next `terraform apply` tries to create everything again
- Duplicate resources are created (or errors if names/IPs conflict)
- Original resources become "orphaned" (not managed by Terraform anymore)

**Solution**:
- Use remote state with versioning enabled
- Restore from backup
- Use `terraform import` to re-import orphaned resources

---

### Danger #3: Secrets in State

**Problem**: State files can contain secrets in plaintext.

Example:
```hcl
resource "aws_db_instance" "main" {
  username = "admin"
  password = "super-secret-password"  # This ends up in state file!
}
```

The state file will contain:
```json
{
  "attributes": {
    "password": "super-secret-password"  # ← EXPOSED IN STATE
  }
}
```

**Solutions:**

1. **Encrypt state file** (S3 backend with encryption)
2. **Use sensitive variables**:
   ```hcl
   variable "db_password" {
     type      = string
     sensitive = true  # Won't show in logs
   }
   ```
3. **Use secrets managers**:
   ```hcl
   data "aws_secretsmanager_secret_version" "db_password" {
     secret_id = "prod/db/password"
   }

   resource "aws_db_instance" "main" {
     password = data.aws_secretsmanager_secret_version.db_password.secret_string
   }
   ```

---

### Danger #4: Manual Changes

**Scenario**: Someone manually deletes a resource in AWS console.

```
Terraform state: "Instance i-12345 exists"
AWS reality: Instance i-12345 doesn't exist
Next apply: Terraform might get confused or recreate unexpectedly
```

**Detection**:
```bash
terraform plan  # Will show that resource needs to be created again
```

**Solution**:
```bash
terraform refresh  # Updates state to match reality
# OR
terraform apply -refresh-only  # Safer, shows what will change first
```

**Prevention**: Train team to never manually change Terraform-managed resources.

---

### Danger #5: State Drift

**Scenario**: Someone manually changes a resource (but doesn't delete it).

```
Terraform state: Instance type = t3.medium
AWS reality: Instance type = t3.large (someone resized it manually)
```

**What happens on next apply:**
- Terraform sees the drift
- Depending on the resource, might:
  - Update it back to `t3.medium` (undoing the manual change)
  - Replace the resource entirely (destroy and recreate)

**Detection**:
```bash
terraform plan  # Shows drift

~ resource "aws_instance" "web" {
    ~ instance_type = "t3.large" -> "t3.medium"  # Will change back
  }
```

**Best Practice**: Embrace drift detection as a feature - it keeps your infrastructure in sync with code.

---

## Summary: The 10 Core Truths

1. **Terraform is declarative** - You describe WHAT, not HOW
2. **Terraform uses state** - It's a ledger of what exists
3. **Always use remote state** - Local state is for learning only
4. **State locking prevents corruption** - Use DynamoDB or equivalent
5. **Always run `plan` before `apply`** - No exceptions
6. **Never manually change Terraform-managed resources** - Use Terraform for everything
7. **State files contain secrets** - Encrypt them
8. **Providers are plugins** - They talk to APIs
9. **Resources create, data sources read** - Know the difference
10. **Terraform is idempotent** - Run it 100 times = same result

---

## What's Next?

You now understand:
- ✅ What Terraform is and why it exists
- ✅ Declarative vs imperative
- ✅ The Terraform workflow
- ✅ Providers, resources, and data sources
- ✅ State files and why they're critical
- ✅ Common dangers and how to avoid them

**Next up**: [Terraform Internals](02-internals.md) - How Terraform actually works under the hood.

This is where you go from "I can use Terraform" to "I understand Terraform."

---

**Questions to test your understanding:**

1. What's the difference between desired state, recorded state, and actual state?
2. Why is Terraform idempotent?
3. What happens if two people run `terraform apply` at the same time without state locking?
4. When should you use a data source vs a resource?
5. Why should you never manually change Terraform-managed infrastructure?

If you can answer these confidently, you're ready to move on. 🚀
