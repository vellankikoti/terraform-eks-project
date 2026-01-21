# 02 - Terraform Internals: How Terraform Actually Works

> **Goal**: Understand Terraform's internal mechanics so you can debug production issues and make expert-level design decisions.

---

## Table of Contents

1. [The Dependency Graph](#1-the-dependency-graph)
2. [How `terraform plan` Really Works](#2-how-terraform-plan-really-works)
3. [State Locking Deep Dive](#3-state-locking-deep-dive)
4. [Drift Detection and Reconciliation](#4-drift-detection-and-reconciliation)
5. [count vs for_each in Production](#5-count-vs-for_each-in-production)
6. [Resource Lifecycle](#6-resource-lifecycle)
7. [Immutable Infrastructure Mindset](#7-immutable-infrastructure-mindset)
8. [Debugging Terraform](#8-debugging-terraform)

---

## 1. The Dependency Graph

### What Is It?

When you write Terraform code, you're defining resources that depend on each other. Terraform builds a **directed acyclic graph (DAG)** to figure out:

1. **What order to create resources** (dependencies first)
2. **What can be created in parallel** (independent resources)
3. **What needs to be destroyed first** (reverse order)

### Simple Example

```hcl
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_subnet" "public" {
  vpc_id     = aws_vpc.main.id  # ← Depends on VPC
  cidr_block = "10.0.1.0/24"
}

resource "aws_instance" "web" {
  ami           = "ami-12345"
  subnet_id     = aws_subnet.public.id  # ← Depends on subnet
  instance_type = "t3.medium"
}
```

**Terraform builds this graph:**

```
aws_vpc.main
    ↓
aws_subnet.public
    ↓
aws_instance.web
```

**Creation order:**
1. Create VPC
2. Create subnet (after VPC is ready)
3. Create instance (after subnet is ready)

**Destruction order:** (Reverse!)
1. Destroy instance
2. Destroy subnet
3. Destroy VPC

### Implicit vs Explicit Dependencies

#### Implicit Dependencies (Automatic)

When you reference one resource in another, Terraform automatically creates a dependency:

```hcl
resource "aws_security_group" "web" {
  vpc_id = aws_vpc.main.id  # ← Implicit dependency
}
```

Terraform knows: "Security group needs VPC to exist first."

#### Explicit Dependencies (Manual)

Sometimes you need to enforce an order even when there's no reference:

```hcl
resource "aws_instance" "web" {
  ami           = "ami-12345"
  instance_type = "t3.medium"

  depends_on = [
    aws_iam_role_policy_attachment.example  # ← Explicit dependency
  ]
}
```

**Use case**: Ensure IAM policy is attached before launching the instance (even though the instance doesn't directly reference the policy).

### Visualizing the Graph

```bash
terraform graph | dot -Tpng > graph.png
```

This creates a visual representation of your dependency graph.

**Example output** (simplified):

```
       ┌─────────┐
       │   VPC   │
       └────┬────┘
            │
     ┌──────┴──────┐
     ↓             ↓
 ┌────────┐   ┌────────┐
 │Subnet 1│   │Subnet 2│  ← Can be created in parallel
 └───┬────┘   └───┬────┘
     │            │
     ↓            ↓
 ┌────────┐   ┌────────┐
 │  EC2 1 │   │  EC2 2 │  ← Can be created in parallel
 └────────┘   └────────┘
```

### Parallelism

By default, Terraform creates **up to 10 resources in parallel** (if they don't depend on each other).

```bash
terraform apply -parallelism=20  # Increase to 20 parallel operations
```

**Why it matters:**
- Creating 100 independent resources sequentially = slow
- Creating them in parallel (10 at a time) = much faster

**Warning**: Setting parallelism too high can hit API rate limits.

---

## 2. How `terraform plan` Really Works

### The Five Phases

When you run `terraform plan`, here's what happens under the hood:

```
Phase 1: Parse Configuration
   ↓
Phase 2: Load State
   ↓
Phase 3: Refresh (Query Real Infrastructure)
   ↓
Phase 4: Build Dependency Graph
   ↓
Phase 5: Calculate Diff and Create Plan
```

Let's break down each phase.

---

### Phase 1: Parse Configuration

**What happens:**
1. Terraform reads all `*.tf` files in the directory
2. Parses HCL (HashiCorp Configuration Language)
3. Validates syntax
4. Resolves variables and locals

**Errors caught here:**
```hcl
resource "aws_instance" "web" {
  ami = "ami-12345"
  # Missing required field: instance_type
}
```

```
Error: Missing required argument
│ The argument "instance_type" is required, but no definition was found.
```

---

### Phase 2: Load State

**What happens:**
1. Terraform reads `terraform.tfstate` (or queries remote backend)
2. Loads the recorded state into memory
3. Acquires state lock (if remote backend supports it)

**State file contains:**
- Resource IDs
- Current attribute values
- Metadata (dependencies, provider info)

**If state is missing:**
- Terraform thinks nothing exists
- Will try to create everything from scratch

---

### Phase 3: Refresh (Query Real Infrastructure)

**What happens:**
1. For each resource in state, Terraform queries the cloud provider
2. Compares recorded state vs actual state
3. Updates in-memory state with real values

**Example:**

```
State says: instance type = t3.medium
AWS says: instance type = t3.large (manual change!)
Terraform updates in-memory state to t3.large
```

**Skip refresh** (faster, but doesn't detect drift):
```bash
terraform plan -refresh=false
```

**Refresh only** (update state without making changes):
```bash
terraform apply -refresh-only
```

---

### Phase 4: Build Dependency Graph

**What happens:**
1. Terraform analyzes resource references
2. Builds a directed acyclic graph (DAG)
3. Determines creation order

**Example:**

```hcl
resource "aws_vpc" "main" { ... }
resource "aws_subnet" "a" { vpc_id = aws_vpc.main.id }
resource "aws_subnet" "b" { vpc_id = aws_vpc.main.id }
resource "aws_instance" "x" { subnet_id = aws_subnet.a.id }
resource "aws_instance" "y" { subnet_id = aws_subnet.b.id }
```

**Graph:**
```
      VPC
      ↓ ↓
   Subnet A   Subnet B  ← Parallel
      ↓         ↓
  Instance X  Instance Y  ← Parallel
```

---

### Phase 5: Calculate Diff and Create Plan

**What happens:**
1. Compares desired state (code) vs current state (refreshed state)
2. Calculates what needs to change
3. Creates an execution plan

**Output symbols:**

| Symbol | Meaning | Example |
|--------|---------|---------|
| `+` | Create | New resource |
| `-` | Destroy | Remove resource |
| `~` | Update in-place | Change instance type without replacement |
| `-/+` | Replace | Destroy then create (e.g., change AMI) |
| `<=` | Read | Data source lookup |

**Example output:**

```
Terraform will perform the following actions:

  # aws_instance.web will be updated in-place
  ~ resource "aws_instance" "web" {
        id            = "i-12345"
      ~ instance_type = "t3.medium" -> "t3.large"  # In-place update
    }

  # aws_instance.db must be replaced
  -/+ resource "aws_instance" "db" {
      ~ ami           = "ami-old" -> "ami-new"  # Force replacement
        instance_type = "t3.medium"
    }

Plan: 1 to add, 1 to change, 1 to destroy.
```

---

### Why Some Changes Force Replacement

Some resource attributes **cannot be changed in-place**. Changing them requires destroying and recreating.

**Examples:**

| Resource | Attribute | Why Replacement? |
|----------|-----------|------------------|
| `aws_instance` | `ami` | Can't change OS on running instance |
| `aws_instance` | `availability_zone` | Can't move instance to different AZ |
| `aws_db_instance` | `storage_encrypted` | Can't encrypt existing database |
| `aws_s3_bucket` | `bucket` (name) | Bucket names are globally unique |

**Force replacement** (even if not required):
```hcl
resource "aws_instance" "web" {
  ami           = "ami-12345"
  instance_type = "t3.medium"

  lifecycle {
    replace_triggered_by = [aws_ami.custom.id]  # Replace if AMI changes
  }
}
```

---

## 3. State Locking Deep Dive

### The Problem

**Without locking:**

```
Time    Engineer A                Engineer B
────────────────────────────────────────────────
10:00   Reads state (version 1)
10:01                             Reads state (version 1)
10:02   Makes changes
10:03   Writes state (version 2)
10:04                             Makes changes
10:05                             Writes state (version 2) ← OVERWRITES A's changes!
```

**Result:** State corruption. Engineer A's changes are lost.

---

### The Solution: DynamoDB Locking

**S3 + DynamoDB Backend:**

```hcl
terraform {
  backend "s3" {
    bucket         = "my-terraform-state"
    key            = "prod/terraform.tfstate"
    region         = "us-east-1"

    # State locking
    dynamodb_table = "terraform-locks"
    encrypt        = true
  }
}
```

**How it works:**

1. Engineer A runs `terraform apply`
2. Terraform writes a lock entry to DynamoDB:
   ```json
   {
     "LockID": "my-terraform-state/prod/terraform.tfstate-md5",
     "Info": "Locked by engineer-a at 2024-01-15 10:00:00",
     "Who": "engineer-a@laptop",
     "Operation": "apply"
   }
   ```
3. Engineer B tries to run `terraform apply`
4. Terraform tries to acquire lock → **BLOCKED**:
   ```
   Error: Error acquiring the state lock
   Lock Info:
     ID:        abc123
     Path:      my-terraform-state/prod/terraform.tfstate
     Operation: apply
     Who:       engineer-a@laptop
     Created:   2024-01-15 10:00:00 UTC

   Terraform acquires a state lock to protect the state from being written
   by multiple users at the same time. Please resolve the issue above and try
   again. For most commands, you can disable locking with the "-lock=false"
   flag, but this is not recommended.
   ```
5. Engineer A's apply finishes
6. Terraform releases the lock
7. Engineer B can now proceed

---

### DynamoDB Table Schema

**Required table configuration:**

```hcl
resource "aws_dynamodb_table" "terraform_locks" {
  name         = "terraform-locks"
  billing_mode = "PAY_PER_REQUEST"  # Or PROVISIONED with low RCU/WCU
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"  # String
  }

  tags = {
    Name        = "Terraform State Lock Table"
    Environment = "production"
  }
}
```

**Important:**
- Hash key MUST be named `LockID`
- Type MUST be String (`S`)
- Pay-per-request is fine (locking is infrequent)

---

### Force Unlock (Dangerous!)

**If a lock is stuck** (e.g., laptop crashed mid-apply):

```bash
terraform force-unlock <LOCK_ID>
```

**Example:**
```bash
terraform force-unlock abc123-def456-ghi789
```

**⚠️ WARNING:** Only do this if you're **absolutely sure** no one else is applying changes.

---

### Other Backend Options

| Backend | Locking Support | Notes |
|---------|-----------------|-------|
| S3 + DynamoDB | ✅ Yes | Production standard for AWS |
| Terraform Cloud | ✅ Yes | Managed locking, free tier available |
| Azure Blob Storage | ✅ Yes | Uses blob leases |
| GCS (Google Cloud Storage) | ✅ Yes | Native locking |
| Local | ❌ No | Never use in teams |

---

## 4. Drift Detection and Reconciliation

### What Is Drift?

**Drift** = When real infrastructure differs from what Terraform expects.

**Causes:**
1. Manual changes via console/CLI
2. Auto-scaling (if not managed by Terraform)
3. Security/compliance tools making automatic changes
4. AWS making changes (e.g., security patches)

---

### Detecting Drift

**Option 1: terraform plan**

```bash
terraform plan
```

Output shows drift:
```
Note: Objects have changed outside of Terraform

Terraform detected the following changes made outside of Terraform since the
last "terraform apply":

  # aws_instance.web has changed
  ~ resource "aws_instance" "web" {
        id            = "i-12345"
      ~ instance_type = "t3.large" -> (known after apply)
        # (10 unchanged attributes hidden)
    }

Unless you have made equivalent changes to your configuration, or ignored the
relevant attributes using ignore_changes, the following plan may include
actions to undo or respond to these changes.
```

**Option 2: terraform plan -refresh-only**

```bash
terraform plan -refresh-only
```

Shows what will be updated in state (without making changes):
```
  # aws_instance.web will be updated
  ~ resource "aws_instance" "web" {
        id            = "i-12345"
      ~ instance_type = "t3.medium" -> "t3.large"
    }

This is a refresh-only plan, so Terraform will not take any actions to undo
these. If you were expecting these changes then you can apply this plan to
record the updated values in the Terraform state without changing any remote
objects.
```

**Option 3: terraform apply -refresh-only**

```bash
terraform apply -refresh-only
```

Updates state file to match reality (accepts the drift).

---

### Handling Drift

**Strategy 1: Fix the Drift (Revert to Code)**

```bash
terraform apply
```

Terraform will undo manual changes and enforce the desired state.

**Example:**
- Code says: `instance_type = "t3.medium"`
- Reality: `instance_type = "t3.large"` (manual change)
- `terraform apply` will resize back to `t3.medium`

---

**Strategy 2: Accept the Drift (Update Code)**

If the manual change is correct, update your code:

```hcl
resource "aws_instance" "web" {
  instance_type = "t3.large"  # ← Update to match reality
}
```

Then:
```bash
terraform plan  # Shows no changes
```

---

**Strategy 3: Ignore Specific Attributes**

If an attribute changes frequently (e.g., tags added by compliance tools), ignore it:

```hcl
resource "aws_instance" "web" {
  ami           = "ami-12345"
  instance_type = "t3.medium"

  lifecycle {
    ignore_changes = [tags]  # ← Terraform won't try to "fix" tag changes
  }
}
```

**Use cases:**
- Tags managed by external tools
- Instance metadata changes
- Auto-scaling group sizes

---

### Continuous Drift Detection

**In production, set up automated drift detection:**

**Option 1: Scheduled CI/CD Job**

```yaml
# GitHub Actions example
name: Drift Detection
on:
  schedule:
    - cron: '0 */6 * * *'  # Every 6 hours

jobs:
  detect-drift:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v2
      - name: Terraform Plan
        run: terraform plan -detailed-exitcode
        # Exit code 2 = changes detected (drift!)
      - name: Notify if drift
        if: failure()
        run: |
          echo "Drift detected! Alert the team."
          # Send Slack/PagerDuty/email notification
```

**Option 2: Terraform Cloud (Drift Detection Feature)**

Terraform Cloud has built-in drift detection that runs automatically.

---

## 5. count vs for_each in Production

### The Problem with count

**Example: Create 3 instances**

```hcl
resource "aws_instance" "web" {
  count = 3

  ami           = "ami-12345"
  instance_type = "t3.medium"

  tags = {
    Name = "web-${count.index}"  # web-0, web-1, web-2
  }
}
```

**Resources created:**
- `aws_instance.web[0]`
- `aws_instance.web[1]`
- `aws_instance.web[2]`

**The disaster scenario:**

You want to remove `web-1`:

```hcl
count = 2  # Reduce from 3 to 2
```

**What you expect:**
- Delete `web-1`
- Keep `web-0` and `web-2`

**What actually happens:**
```
Terraform will perform the following actions:

  # aws_instance.web[1] will be updated in-place
  ~ resource "aws_instance" "web" {
        # web-1 becomes web-2's name
    }

  # aws_instance.web[2] will be destroyed
  - resource "aws_instance" "web" {
        # web-2 is destroyed!
    }
```

**Why?** Terraform uses array indices. Removing index 1 shifts everything:
- Old `[0, 1, 2]`
- New `[0, 1]` (index 2 is deleted, index 1 is renamed)

---

### The Solution: for_each

```hcl
variable "instances" {
  type = map(object({
    instance_type = string
  }))
  default = {
    "web-0" = { instance_type = "t3.medium" }
    "web-1" = { instance_type = "t3.medium" }
    "web-2" = { instance_type = "t3.medium" }
  }
}

resource "aws_instance" "web" {
  for_each = var.instances

  ami           = "ami-12345"
  instance_type = each.value.instance_type

  tags = {
    Name = each.key  # web-0, web-1, web-2
  }
}
```

**Resources created:**
- `aws_instance.web["web-0"]`
- `aws_instance.web["web-1"]`
- `aws_instance.web["web-2"]`

**Remove `web-1`:**

```hcl
variable "instances" {
  default = {
    "web-0" = { instance_type = "t3.medium" }
    # "web-1" removed
    "web-2" = { instance_type = "t3.medium" }
  }
}
```

**Result:**
```
Terraform will perform the following actions:

  # aws_instance.web["web-1"] will be destroyed
  - resource "aws_instance" "web" {
        # Only web-1 is destroyed, web-0 and web-2 untouched!
    }

Plan: 0 to add, 0 to change, 1 to destroy.
```

**Perfect!** Only the correct resource is destroyed.

---

### When to Use Each

| Use `count` | Use `for_each` |
|-------------|----------------|
| Simple duplication (3 identical things) | Resources with unique identifiers |
| Resources won't be individually added/removed | Adding/removing specific resources |
| Order doesn't matter | Order matters |
| Quick prototyping | Production code |

**Golden Rule**: Use `for_each` in production. Only use `count` for simple, stable duplication.

---

## 6. Resource Lifecycle

### Lifecycle Meta-Arguments

Control how Terraform creates, updates, and destroys resources:

```hcl
resource "aws_instance" "web" {
  ami           = "ami-12345"
  instance_type = "t3.medium"

  lifecycle {
    create_before_destroy = true
    prevent_destroy       = true
    ignore_changes        = [tags]
    replace_triggered_by  = [aws_ami.custom.id]
  }
}
```

---

### 1. create_before_destroy

**Default behavior (destroy first):**
```
1. Destroy old resource
2. Create new resource
   ↑ Downtime between steps 1 and 2!
```

**With create_before_destroy:**
```
1. Create new resource
2. Destroy old resource
   ↑ Zero downtime!
```

**Use case: Databases, load balancers (anything that needs zero downtime)**

```hcl
resource "aws_db_instance" "main" {
  # ...
  lifecycle {
    create_before_destroy = true
  }
}
```

---

### 2. prevent_destroy

**Prevents accidental destruction:**

```hcl
resource "aws_s3_bucket" "important_data" {
  bucket = "my-critical-data"

  lifecycle {
    prevent_destroy = true  # terraform destroy will fail
  }
}
```

**Attempting to destroy:**
```bash
$ terraform destroy

Error: Instance cannot be destroyed

  on main.tf line 5:
   5: resource "aws_s3_bucket" "important_data" {

Resource aws_s3_bucket.important_data has lifecycle.prevent_destroy set, but
the plan calls for this resource to be destroyed. To avoid this error, either
disable lifecycle.prevent_destroy or adjust the plan to not destroy this
resource.
```

**Use case: Production databases, state buckets, critical resources**

---

### 3. ignore_changes

**Ignore changes to specific attributes:**

```hcl
resource "aws_instance" "web" {
  ami           = "ami-12345"
  instance_type = "t3.medium"

  tags = {
    Name = "web-server"
  }

  lifecycle {
    ignore_changes = [tags]  # Don't "fix" tag changes
  }
}
```

**Ignore ALL changes:**
```hcl
lifecycle {
  ignore_changes = all  # Terraform won't manage this resource anymore (except creation)
}
```

**Use cases:**
- Tags managed by external tools
- Attributes changed by auto-scaling
- Resources partially managed by Terraform

---

### 4. replace_triggered_by

**Force replacement when another resource changes:**

```hcl
resource "aws_ami_from_instance" "custom" {
  source_instance_id = "i-12345"
}

resource "aws_instance" "web" {
  ami           = aws_ami_from_instance.custom.id
  instance_type = "t3.medium"

  lifecycle {
    replace_triggered_by = [
      aws_ami_from_instance.custom.id  # Replace instance if AMI changes
    ]
  }
}
```

---

## 7. Immutable Infrastructure Mindset

### What Is Immutable Infrastructure?

**Mutable (Old Way):**
```
1. Create server
2. SSH in and install updates
3. Change configuration files
4. Restart services
   ↑ Server changes over time ("snowflake server")
```

**Problems:**
- Servers drift from each other
- Can't reproduce exact state
- "Works on my machine" issues

**Immutable (Modern Way):**
```
1. Create server from image
2. Never SSH or change it
3. Need an update? Build new image → Launch new server → Destroy old
   ↑ Servers are always freshly built from known image
```

**Benefits:**
- Consistency: All servers identical
- Reproducibility: Can recreate exactly
- Rollback: Keep old image, launch it if new version fails

---

### Terraform Enables Immutable Infrastructure

**Example: Update application version**

**Mutable approach:**
```bash
# SSH into each server
ssh server1
sudo systemctl restart myapp

ssh server2
sudo systemctl restart myapp
# ... repeat for 100 servers
```

**Immutable approach:**
```hcl
# 1. Build new AMI with updated app (using Packer)
# 2. Update Terraform code:

resource "aws_launch_template" "app" {
  image_id = "ami-new-version"  # ← Change AMI
  # ...
}

# 3. Apply:
terraform apply

# Terraform destroys old instances, creates new ones with new AMI
```

---

### Blue/Green Deployments

**Instead of updating existing resources, create new ones alongside:**

```hcl
# Blue environment (current production)
module "blue" {
  source = "./modules/app"
  color  = "blue"
  ami    = "ami-v1.0"
}

# Green environment (new version)
module "green" {
  source = "./modules/app"
  color  = "green"
  ami    = "ami-v2.0"
}

# Load balancer points to blue
resource "aws_lb_target_group_attachment" "production" {
  target_group_arn = aws_lb_target_group.app.arn
  target_id        = module.blue.instance_id  # ← Switch to green when ready
}
```

**Deployment process:**
1. Deploy green environment
2. Test green
3. Switch load balancer to green
4. Destroy blue (or keep for quick rollback)

---

## 8. Debugging Terraform

### Enable Detailed Logging

```bash
export TF_LOG=DEBUG
terraform apply
```

**Log levels:**
- `TRACE` - Most verbose
- `DEBUG` - Detailed info
- `INFO` - General info
- `WARN` - Warnings only
- `ERROR` - Errors only

**Save logs to file:**
```bash
export TF_LOG=DEBUG
export TF_LOG_PATH=terraform.log
terraform apply
```

---

### Common Errors and Fixes

#### Error 1: State Lock Timeout

```
Error: Error acquiring the state lock
```

**Cause:** Another apply is running, or previous apply crashed.

**Fix:**
```bash
# Verify no one else is running apply
# Then force unlock:
terraform force-unlock <LOCK_ID>
```

---

#### Error 2: Resource Already Exists

```
Error: Error creating Instance: InvalidIPAddress.InUse: Address x.x.x.x is already in use
```

**Cause:** Terraform lost track of the resource (state drift).

**Fix:**
```bash
# Import existing resource into state:
terraform import aws_instance.web i-1234567890abcdef
```

---

#### Error 3: Circular Dependency

```
Error: Cycle: aws_security_group.a, aws_security_group.b
```

**Cause:** Two resources depend on each other.

```hcl
# BAD: Circular dependency
resource "aws_security_group" "a" {
  # References security group B
  ingress {
    security_groups = [aws_security_group.b.id]
  }
}

resource "aws_security_group" "b" {
  # References security group A
  ingress {
    security_groups = [aws_security_group.a.id]
  }
}
```

**Fix:** Use `aws_security_group_rule` resources instead:

```hcl
resource "aws_security_group" "a" { }
resource "aws_security_group" "b" { }

resource "aws_security_group_rule" "a_to_b" {
  type                     = "ingress"
  security_group_id        = aws_security_group.a.id
  source_security_group_id = aws_security_group.b.id
}

resource "aws_security_group_rule" "b_to_a" {
  type                     = "ingress"
  security_group_id        = aws_security_group.b.id
  source_security_group_id = aws_security_group.a.id
}
```

---

#### Error 4: Timeout Waiting for Resource

```
Error: timeout while waiting for resource to become ready
```

**Cause:** Resource is slow to create, or creation failed silently.

**Fix:**
1. Check AWS console - is the resource stuck?
2. Increase timeout (if provider supports it):
   ```hcl
   resource "aws_db_instance" "main" {
     # ...
     timeouts {
       create = "60m"  # Default might be too short
     }
   }
   ```

---

## Summary: The Expert's Checklist

- ✅ Understand dependency graphs (implicit and explicit)
- ✅ Know the 5 phases of `terraform plan`
- ✅ Always use state locking (S3 + DynamoDB)
- ✅ Set up automated drift detection
- ✅ Use `for_each` in production (not `count`)
- ✅ Use lifecycle meta-arguments strategically
- ✅ Think immutably: replace, don't mutate
- ✅ Know how to debug with `TF_LOG`

---

## What's Next?

You now understand Terraform's internals at a deep level. You can:
- Debug complex dependency issues
- Design state locking strategies
- Handle drift intelligently
- Choose `count` vs `for_each` correctly
- Use lifecycle rules to prevent outages

**Next up**: [Production EKS Setup](04-eks-production.md) - Apply this knowledge to build a real production system.

This is where theory meets reality. 🚀
