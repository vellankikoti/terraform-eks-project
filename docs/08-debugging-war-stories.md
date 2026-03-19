# 08 - Debugging & War Stories: Lessons Written in Blood and Downtime

> **Goal**: Learn from the most painful, expensive, and career-defining infrastructure failures so you never have to live them yourself. Each story is real. Each lesson was expensive. Read them at 2 PM so you never have to learn them at 2 AM.

---

## Table of Contents

1. [The Debugging Mindset](#1-the-debugging-mindset)
2. [War Story #1: The State File Disaster](#2-war-story-1-the-state-file-disaster)
3. [War Story #2: The EKS Upgrade That Took Down Production](#3-war-story-2-the-eks-upgrade-that-took-down-production)
4. [War Story #3: The $43,000 NAT Gateway Bill](#4-war-story-3-the-43000-nat-gateway-bill)
5. [War Story #4: The Circular Dependency Deadlock](#5-war-story-4-the-circular-dependency-deadlock)
6. [War Story #5: The "Tainted" Resource Cascade](#6-war-story-5-the-tainted-resource-cascade)
7. [War Story #6: The Secrets in State File Breach](#7-war-story-6-the-secrets-in-state-file-breach)
8. [War Story #7: The Cross-Region Replication Failure](#8-war-story-7-the-cross-region-replication-failure)
9. [War Story #8: The Helm Release That Wouldn't Die](#9-war-story-8-the-helm-release-that-wouldnt-die)
10. [War Story #9: The Autoscaler That Scaled to Infinity](#10-war-story-9-the-autoscaler-that-scaled-to-infinity)
11. [War Story #10: The DNS Propagation Nightmare](#11-war-story-10-the-dns-propagation-nightmare)
12. [Essential Debugging Commands](#12-essential-debugging-commands)
13. [The Post-Mortem Template](#13-the-post-mortem-template)
14. [Test Yourself: Debugging Scenarios](#14-test-yourself-debugging-scenarios)

---

## 1. The Debugging Mindset

### What Separates Senior Engineers from Everyone Else

It is 3:17 AM. Your phone is screaming. PagerDuty says production is down. Your heart rate spikes. Your palms sweat. You open your laptop and stare at a wall of red.

This is the moment that separates senior engineers from everyone else.

It is not about knowing more commands. It is not about being faster. It is about **how you think** when everything is on fire.

### The Systematic Debugging Framework

Experts follow a framework, even when panicking internally. Tape this to your monitor:

```
    +------------------------------------------------------------------+
    |              THE DEBUGGING LOOP                                   |
    |                                                                   |
    |   +-----------+     +-------------+     +--------+               |
    |   |  OBSERVE  | --> | HYPOTHESIZE | --> |  TEST  |               |
    |   +-----------+     +-------------+     +--------+               |
    |        ^                                     |                    |
    |        |                                     v                    |
    |   +----------+     +--------+          +----------+              |
    |   | DOCUMENT | <-- | VERIFY | <-----   |   FIX    |              |
    |   +----------+     +--------+          +----------+              |
    |                                                                   |
    +------------------------------------------------------------------+
```

**Step 1: OBSERVE** -- Do not touch anything. Gather data. Read logs. Check metrics. What changed recently? What does the error actually say?

**Step 2: HYPOTHESIZE** -- Based on what you see, form exactly ONE theory. Write it down. "I believe the issue is X because I observed Y."

**Step 3: TEST** -- Design a test that proves or disproves your hypothesis. Not a fix. A test. There is a critical difference.

**Step 4: FIX** -- Only after you understand the problem, apply the smallest possible fix. Resist the urge to "fix everything while you are in there."

**Step 5: VERIFY** -- Confirm the fix worked. Check upstream and downstream. Did fixing A break B?

**Step 6: DOCUMENT** -- Write it down while it is fresh. Tomorrow-you will not remember why you ran that command at 4 AM.

### Why Panic Makes Everything Worse

```
Panic Mode:
  "Something is broken!" --> randomly restart services
                         --> change 5 things at once
                         --> forget what you changed
                         --> now 3 things are broken instead of 1
                         --> bigger panic

Expert Mode:
  "Something is broken." --> breathe
                          --> open a shared doc / incident channel
                          --> timestamp every action
                          --> change ONE thing at a time
                          --> verify after each change
```

The single worst thing you can do during an outage is change multiple things simultaneously. You will never know what fixed it, and you might introduce new problems you will discover next week at 3 AM.

### The "5 Whys" for Infrastructure Failures

Toyota invented this. It works for servers too.

```
Problem: Production is down.

Why #1: Why is production down?
  --> The EKS nodes are unresponsive.

Why #2: Why are the EKS nodes unresponsive?
  --> They ran out of disk space.

Why #3: Why did they run out of disk space?
  --> Container logs filled the disk because log rotation was not configured.

Why #4: Why was log rotation not configured?
  --> Our Terraform node group template does not include log rotation in the user data.

Why #5: Why does our template not include log rotation?
  --> We copied a basic example from a blog post and never hardened it.

ROOT CAUSE: No infrastructure hardening checklist for production node groups.
ACTION ITEM: Create a hardened node group module with log rotation, monitoring
             agent, and disk space alerts baked in.
```

Notice how the root cause is never the first answer. The first answer is a symptom. Keep asking "why" until you hit a **process or system failure** -- that is where the real fix lives.

---

## 2. War Story #1: The State File Disaster

### The Setup

Monday morning. A team of three engineers manages a production EKS cluster running 14 microservices. Their Terraform state is stored locally in `terraform.tfstate` on a shared EC2 "management" instance. They have been meaning to move to S3 remote state "next sprint" for six months.

### The Crisis

Engineer A is cleaning up old files on the management instance to free disk space. They run:

```bash
# What they meant to do
rm -rf /tmp/old-terraform-runs/

# What they actually typed
rm -rf /home/deploy/terraform/terraform.tfstate*
```

The tab-completion betrayed them. The state file, the backup state file, and any local state snapshots -- gone.

Engineer A's stomach drops. They run `ls` again, hoping they misread the output. The files are gone.

Production is still running perfectly. The EKS cluster, the VPC, the node groups, the load balancers -- all humming along. But Terraform now believes **none of it exists**.

### The Investigation

```bash
# Engineer A tries a plan, hoping for the best
terraform plan

# Output (the stuff of nightmares):
# Plan: 47 to add, 0 to change, 0 to destroy.
#
# Terraform wants to CREATE everything from scratch.
# But those resources ALREADY EXIST in AWS.
```

If they run `terraform apply` now, Terraform will attempt to create duplicate resources. Some will fail with name conflicts. Others will create expensive duplicates. The IAM roles might collide. The VPC CIDR will conflict. It would be chaos.

### The Recovery: The Import Marathon

The team spent the next 14 hours importing every resource back into state. Here is what that looks like:

```bash
# Step 1: List what actually exists in AWS
aws ec2 describe-vpcs --filters "Name=tag:Project,Values=our-project"
aws eks describe-cluster --name production-cluster
aws ec2 describe-subnets --filters "Name=vpc-id,Values=vpc-0abc123"

# Step 2: Import each resource, one at a time

# The VPC
terraform import module.vpc.aws_vpc.this vpc-0abc123def456

# Each subnet (they had 6)
terraform import module.vpc.aws_subnet.public[0] subnet-0aaa111
terraform import module.vpc.aws_subnet.public[1] subnet-0bbb222
terraform import module.vpc.aws_subnet.private[0] subnet-0ccc333
terraform import module.vpc.aws_subnet.private[1] subnet-0ddd444
terraform import module.vpc.aws_subnet.private[2] subnet-0eee555
terraform import module.vpc.aws_subnet.private[3] subnet-0fff666

# The internet gateway
terraform import module.vpc.aws_internet_gateway.this igw-0abc123

# NAT Gateways
terraform import module.vpc.aws_nat_gateway.this[0] nat-0aaa111
terraform import module.vpc.aws_nat_gateway.this[1] nat-0bbb222

# Route tables (4 of them, plus associations)
terraform import module.vpc.aws_route_table.public rtb-0aaa111
terraform import module.vpc.aws_route_table.private[0] rtb-0bbb222
# ... and so on for every single resource

# EKS cluster
terraform import module.eks.aws_eks_cluster.this production-cluster

# Node groups
terraform import module.eks.aws_eks_node_group.workers production-cluster:worker-nodes

# Security groups (the worst part -- dozens of rules)
terraform import module.eks.aws_security_group.cluster sg-0abc123
terraform import module.eks.aws_security_group_rule.cluster_ingress_443 sg-0abc123_ingress_tcp_443_443_0.0.0.0/0

# IAM roles and policies
terraform import module.eks.aws_iam_role.cluster production-eks-cluster-role
terraform import module.eks.aws_iam_role_policy_attachment.cluster_AmazonEKSClusterPolicy \
  production-eks-cluster-role/arn:aws:iam::aws:policy/AmazonEKSClusterPolicy

# ... 50+ more resources
```

After importing, they ran `terraform plan` and saw drift:

```
# After importing everything:
terraform plan

# Output:
# Plan: 0 to add, 12 to change, 0 to destroy.
#
# Terraform found differences between imported state and code.
# Tags were slightly different. Security group descriptions didn't match.
# Minor attribute differences everywhere.
```

They had to reconcile each difference -- updating their Terraform code to match reality or accepting the planned changes.

### The Timeline

```
09:00  State file deleted
09:05  Engineer A realizes what happened, panic sets in
09:15  Team assembles, begins AWS inventory
09:30  Start importing resources
12:00  VPC and networking imported (23 resources)
14:00  EKS cluster and node groups imported (12 resources)
16:00  IAM roles and policies imported (11 resources)
18:00  Security groups and rules imported (the worst: 15 resources)
20:00  First clean terraform plan with 0 to destroy
21:00  Reconcile 12 planned changes, update code
23:00  Clean plan: "No changes. Your infrastructure matches the configuration."
23:30  Migrate state to S3 with versioning and DynamoDB locking
```

### The Lessons

**Lesson 1**: Use remote state from day one. Not "next sprint." Day one.

```hcl
# This should be the FIRST thing you write
terraform {
  backend "s3" {
    bucket         = "company-terraform-state"
    key            = "production/eks/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-state-lock"

    # S3 versioning means you can ALWAYS recover previous state
    # Enable versioning on the S3 bucket itself
  }
}
```

**Lesson 2**: Enable S3 bucket versioning on your state bucket.

```hcl
resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.terraform_state.id
  versioning_configuration {
    status = "Enabled"
  }
}
```

If the state gets corrupted, you can recover any previous version.

**Lesson 3**: Never store state locally for anything that matters. "Matters" means anything that is not a personal experiment you can destroy and recreate in 5 minutes.

**Lesson 4**: Tag everything. The only reason this team recovered in 14 hours instead of 14 days is that their resources were tagged. Without tags, finding 50+ AWS resource IDs across a busy account would be nearly impossible.

---

## 3. War Story #2: The EKS Upgrade That Took Down Production

### The Setup

A startup runs their entire SaaS product on EKS 1.27. They have 8 services, 3 node groups, and about 40 pods. Business is good. A well-meaning engineer notices EKS 1.28 has been out for a while and decides to upgrade.

### The Crisis

The change looks innocent:

```hcl
# The one-line change that caused a 45-minute outage
module "eks" {
  source          = "terraform-aws-modules/eks/aws"
  cluster_version = "1.28"    # Was "1.27"
  # ...
}
```

They run `terraform plan`:

```
# Plan output (they didn't read this carefully enough):
#
# ~ module.eks.aws_eks_cluster.this
#     ~ version: "1.27" -> "1.28"
#
# -/+ module.eks.aws_eks_node_group.workers (forces replacement)
#     ~ ami_type:      "AL2_x86_64" -> "AL2_x86_64"
#     ~ release_version: "1.27.9-20231211" -> (known after apply)
#
# Plan: 1 to add, 1 to change, 1 to destroy.
```

Did you catch it? `-/+` means **destroy and recreate**. The node group must be replaced because the AMI version is tied to the cluster version. When the node group is destroyed, **every pod on every node gets evicted simultaneously**.

They ran `terraform apply`. Confirmed with `yes`.

### The Catastrophe Unfolds

```
Timeline:
  T+0:00  terraform apply begins
  T+2:00  EKS control plane upgrade starts (this part is fine, AWS handles it)
  T+8:00  Control plane upgrade complete
  T+8:30  Terraform begins destroying the old node group
  T+9:00  AWS starts draining nodes -- ALL OF THEM AT ONCE
  T+9:30  All pods enter Terminating state
  T+10:00 PagerDuty goes ballistic. Every health check fails.
  T+10:30 New node group creation begins
  T+14:00 New nodes register with the cluster
  T+15:00 Pods start scheduling on new nodes
  T+20:00 Container images pulling (some are 2GB+)
  T+35:00 Most pods are Running
  T+45:00 All pods healthy, health checks green
```

Forty-five minutes of complete downtime. During business hours. On a Tuesday.

### What PodDisruptionBudgets Did (and Did Not Do)

Some services had PodDisruptionBudgets:

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: api-gateway-pdb
spec:
  minAvailable: 2
  selector:
    matchLabels:
      app: api-gateway
```

PDBs protect against voluntary disruptions -- like a `kubectl drain`. When a node group is replaced, AWS attempts to drain nodes gracefully and PDBs can slow down the drain to maintain availability. But when **all nodes** are being terminated and there is nowhere for pods to reschedule to, PDBs just delay the inevitable. The pods had no healthy nodes to move to because the new node group did not exist yet.

### The Correct Upgrade Procedure

Here is how to upgrade EKS with zero downtime:

```
+------------------------------------------------------------------+
|                  SAFE EKS UPGRADE PROCEDURE                       |
|                                                                   |
|  Phase 1: Preparation                                             |
|  +------------------+                                             |
|  | Check EKS        |  Review release notes, deprecated APIs,    |
|  | release notes    |  addon compatibility                       |
|  +------------------+                                             |
|           |                                                       |
|  Phase 2: Control Plane                                           |
|  +------------------+                                             |
|  | Upgrade cluster  |  Update cluster_version only.              |
|  | version ONLY     |  Do NOT touch node groups yet.             |
|  +------------------+                                             |
|           |                                                       |
|  Phase 3: Rolling Node Update                                     |
|  +------------------+                                             |
|  | Create NEW node  |  New group runs 1.28, old still runs 1.27  |
|  | group (blue)     |  Pods stay on old nodes. Nothing moves.    |
|  +------------------+                                             |
|           |                                                       |
|  +------------------+                                             |
|  | Cordon old nodes |  No new pods scheduled on old nodes.       |
|  +------------------+                                             |
|           |                                                       |
|  +------------------+                                             |
|  | Drain old nodes  |  Pods migrate to new nodes one by one.     |
|  | one at a time    |  PDBs are respected. Zero downtime.        |
|  +------------------+                                             |
|           |                                                       |
|  Phase 4: Cleanup                                                 |
|  +------------------+                                             |
|  | Remove old node  |  Only after ALL pods are healthy on new.   |
|  | group            |                                             |
|  +------------------+                                             |
+------------------------------------------------------------------+
```

In Terraform, this means:

```hcl
# Step 1: Upgrade the control plane ONLY
module "eks" {
  cluster_version = "1.28"

  # Keep the old node group EXACTLY as is
  eks_managed_node_groups = {
    workers_v127 = {
      ami_type       = "AL2_x86_64"
      instance_types = ["m5.large"]
      min_size       = 2
      max_size       = 5
      desired_size   = 3
    }
  }
}

# Step 2: In a SEPARATE apply, add the new node group alongside the old
module "eks" {
  cluster_version = "1.28"

  eks_managed_node_groups = {
    # OLD -- still running
    workers_v127 = {
      ami_type       = "AL2_x86_64"
      instance_types = ["m5.large"]
      min_size       = 2
      max_size       = 5
      desired_size   = 3
    }
    # NEW -- fresh nodes with 1.28 AMI
    workers_v128 = {
      ami_type       = "AL2_x86_64"
      instance_types = ["m5.large"]
      min_size       = 2
      max_size       = 5
      desired_size   = 3
    }
  }
}

# Step 3: Manually cordon and drain old nodes
# kubectl cordon <old-node-1>
# kubectl drain <old-node-1> --ignore-daemonsets --delete-emptydir-data

# Step 4: After all pods are on new nodes, remove old node group
# Remove workers_v127 from Terraform code, then apply
```

### The Lessons

**Lesson 1**: `-/+` in a Terraform plan means DESTROY then CREATE. Read plans like your job depends on it, because it does.

**Lesson 2**: Never upgrade the cluster version and node groups in the same apply.

**Lesson 3**: Use the blue-green node group pattern for upgrades.

**Lesson 4**: Always have PodDisruptionBudgets, but understand they are not a safety net against simultaneous full-node-group replacement.

---

## 4. War Story #3: The $43,000 NAT Gateway Bill

### The Setup

A fast-growing team deploys their EKS cluster in private subnets (correct for security). Their nodes pull container images from ECR, communicate with S3 for logs, and call various AWS APIs. All of this traffic flows through NAT Gateways.

Nobody thinks about this. The architecture diagram looks right. The security review passes.

### The Crisis

The AWS bill arrives. The finance team calls an emergency meeting.

```
Previous month:    $4,200  (normal)
This month:       $43,847  (not normal)

Breakdown of the surprise:
  NAT Gateway - Data Processing:  $38,420
  NAT Gateway - Hourly:           $    67
  EC2 instances:                  $ 3,100
  Everything else:                $ 2,260
```

Thirty-eight thousand dollars. In NAT Gateway data transfer charges. In a single month.

### The Investigation

The team traces the data flow:

```
+------------------------------------------------------------------+
|              THE EXPENSIVE DATA PATH                              |
|                                                                   |
|  Private Subnet                     Public Internet               |
|  +------------------+               +-------------------+         |
|  | EKS Node         |               | ECR Public        |         |
|  |                  |    NAT GW     | Endpoint          |         |
|  | docker pull -->  | --($$$$$)--> | (images)          |         |
|  | image:latest     |               |                   |         |
|  +------------------+               +-------------------+         |
|                                                                   |
|  Every pod restart = full image pull                              |
|  50 pods x 30 restarts/day x 2GB image = 3TB/day                 |
|  NAT Gateway charges: $0.045 per GB                               |
|  3TB x 30 days x $0.045 = $4,050/month ... for ONE image         |
+------------------------------------------------------------------+
```

But it was worse than that. They had:
- 14 microservices, each with 500MB-2GB images
- No image pull caching (imagePullPolicy: Always)
- Pods crashing and restarting frequently (a separate bug)
- CloudWatch logs flowing through NAT to the CloudWatch endpoint
- S3 uploads for user content going through NAT

Total data through NAT: approximately 850 GB per day. At $0.045 per GB, that is $38.25/day just in processing fees. Over a month: $1,147 just from NAT processing. The bulk of the bill was actually the data transfer charges stacking on top.

### The Fix: VPC Endpoints

VPC endpoints let your private subnets talk to AWS services **without going through NAT**. The traffic stays on Amazon's internal network. It is faster, more reliable, and effectively free.

```hcl
# These endpoints eliminate almost all NAT Gateway traffic to AWS services

# ECR endpoints (for pulling container images)
resource "aws_vpc_endpoint" "ecr_api" {
  vpc_id              = module.vpc.vpc_id
  service_name        = "com.amazonaws.${var.region}.ecr.api"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = module.vpc.private_subnets
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true
}

resource "aws_vpc_endpoint" "ecr_dkr" {
  vpc_id              = module.vpc.vpc_id
  service_name        = "com.amazonaws.${var.region}.ecr.dkr"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = module.vpc.private_subnets
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true
}

# S3 endpoint (Gateway type -- completely free, no hourly charge)
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = module.vpc.vpc_id
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = module.vpc.private_route_table_ids
}

# CloudWatch Logs endpoint
resource "aws_vpc_endpoint" "cloudwatch_logs" {
  vpc_id              = module.vpc.vpc_id
  service_name        = "com.amazonaws.${var.region}.logs"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = module.vpc.private_subnets
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true
}

# STS endpoint (for IRSA / pod identity)
resource "aws_vpc_endpoint" "sts" {
  vpc_id              = module.vpc.vpc_id
  service_name        = "com.amazonaws.${var.region}.sts"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = module.vpc.private_subnets
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true
}

# Security group for VPC endpoints
resource "aws_security_group" "vpc_endpoints" {
  name_prefix = "vpc-endpoints-"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [module.vpc.vpc_cidr_block]
  }
}
```

### The Cost Optimization Playbook

```
Before VPC Endpoints:
  NAT Gateway monthly cost:  $38,420
  VPC Endpoint monthly cost: $     0

After VPC Endpoints:
  NAT Gateway monthly cost:  $   340  (only non-AWS internet traffic remains)
  VPC Endpoint monthly cost: $   220  (Interface endpoints cost ~$7.50/month each)

  Monthly savings:           $37,860
  Annual savings:           $454,320
```

**Prevention: Set up billing alarms before you need them.**

```hcl
resource "aws_cloudwatch_metric_alarm" "nat_gateway_bytes" {
  alarm_name          = "nat-gateway-high-data-transfer"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "BytesOutToDestination"
  namespace           = "AWS/NATGateway"
  period              = 86400  # 1 day
  statistic           = "Sum"
  threshold           = 107374182400  # 100 GB per day
  alarm_description   = "NAT Gateway processed more than 100GB in a day"
  alarm_actions       = [aws_sns_topic.billing_alerts.arn]

  dimensions = {
    NatGatewayId = aws_nat_gateway.main.id
  }
}

resource "aws_budgets_budget" "monthly" {
  name         = "monthly-budget"
  budget_type  = "COST"
  limit_amount = "5000"
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  notification {
    comparison_operator       = "GREATER_THAN"
    threshold                 = 80
    threshold_type            = "PERCENTAGE"
    notification_type         = "ACTUAL"
    subscriber_email_addresses = ["team@company.com"]
  }
}
```

### The Lessons

**Lesson 1**: VPC endpoints are not optional for production EKS. They are mandatory.

**Lesson 2**: Set billing alarms on day one. A $5,000 alarm would have caught this on day 4 instead of day 30.

**Lesson 3**: Audit your NAT Gateway metrics monthly. High data transfer through NAT is almost always a sign that a VPC endpoint is missing.

**Lesson 4**: Use `imagePullPolicy: IfNotPresent` to avoid pulling the same image repeatedly.

---

## 5. War Story #4: The Circular Dependency Deadlock

### The Setup

An engineer is writing security groups for an EKS cluster. The cluster nodes need to talk to the control plane, and the control plane needs to talk back to the nodes. Seems simple:

```hcl
# Security group for the EKS control plane
resource "aws_security_group" "cluster" {
  name_prefix = "eks-cluster-"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.nodes.id]  # <-- References nodes
  }
}

# Security group for the EKS worker nodes
resource "aws_security_group" "nodes" {
  name_prefix = "eks-nodes-"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 10250
    to_port         = 10250
    protocol        = "tcp"
    security_groups = [aws_security_group.cluster.id]  # <-- References cluster
  }
}
```

### The Crisis

```bash
terraform plan

# Error: Cycle: aws_security_group.cluster, aws_security_group.nodes
```

Terraform cannot determine which to create first. Security group A needs B's ID. Security group B needs A's ID. Neither can be created without the other. Deadlock.

Some engineers try to work around this by running apply in pieces, or adding `depends_on` to force ordering. These hacks make things worse.

### The Investigation

The problem is **inline rules**. When you define ingress/egress blocks inside the `aws_security_group` resource, Terraform treats those rules as part of the security group itself. The dependency graph becomes circular.

```
Dependency graph (BROKEN):

  aws_security_group.cluster
         |                ^
         | needs id of    | needs id of
         v                |
  aws_security_group.nodes
```

### The Fix: Separate Rule Resources

The solution is to create the security groups with NO inline rules, then add rules as separate resources:

```hcl
# Step 1: Create both security groups with NO inline rules
resource "aws_security_group" "cluster" {
  name_prefix = "eks-cluster-"
  vpc_id      = var.vpc_id
  description = "EKS cluster control plane"

  # NO ingress or egress blocks here
}

resource "aws_security_group" "nodes" {
  name_prefix = "eks-nodes-"
  vpc_id      = var.vpc_id
  description = "EKS worker nodes"

  # NO ingress or egress blocks here
}

# Step 2: Add rules as SEPARATE resources
resource "aws_security_group_rule" "cluster_ingress_from_nodes" {
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  security_group_id        = aws_security_group.cluster.id
  source_security_group_id = aws_security_group.nodes.id
  description              = "Allow nodes to communicate with control plane"
}

resource "aws_security_group_rule" "nodes_ingress_from_cluster" {
  type                     = "ingress"
  from_port                = 10250
  to_port                  = 10250
  protocol                 = "tcp"
  security_group_id        = aws_security_group.nodes.id
  source_security_group_id = aws_security_group.cluster.id
  description              = "Allow control plane to communicate with nodes"
}
```

Now the dependency graph works:

```
Dependency graph (FIXED):

  aws_security_group.cluster     aws_security_group.nodes
         |                                |
         v                                v
  (created independently -- no cross-references)
         |                                |
         +------+                +--------+
                |                |
                v                v
  aws_security_group_rule.cluster_ingress_from_nodes
  aws_security_group_rule.nodes_ingress_from_cluster

  (rules depend on BOTH groups, but groups don't depend on each other)
```

### The Golden Rule

**Never use inline ingress/egress blocks in `aws_security_group` when two security groups reference each other.** Always use `aws_security_group_rule` or `aws_vpc_security_group_ingress_rule` as separate resources.

In fact, many experienced teams ban inline rules entirely to avoid ever hitting this problem:

```hcl
# Company convention: ALWAYS use separate rules
resource "aws_security_group" "any_group" {
  name_prefix = "example-"
  vpc_id      = var.vpc_id

  # Intentionally empty. All rules defined as aws_security_group_rule resources.
  # See: security_group_rules.tf
}
```

### The Lessons

**Lesson 1**: `Cycle` errors in Terraform almost always mean you have a circular reference. Run `terraform graph | dot -Tsvg > graph.svg` to visualize it.

**Lesson 2**: Separate resources for security group rules eliminate circular dependencies entirely.

**Lesson 3**: If you see `depends_on` used to "fix" a circular dependency, something is architecturally wrong. Fix the structure, not the symptoms.

---

## 6. War Story #5: The "Tainted" Resource Cascade

### The Setup

A senior engineer is debugging a VPC issue. One of the subnets is behaving oddly -- instances in it cannot reach the internet. After some investigation, they decide the subnet might have a misconfigured route table association.

In a moment of questionable judgment, they run:

```bash
# What they THOUGHT this would do: "Mark the subnet for recreation"
terraform taint module.vpc.aws_vpc.this

# What they ACTUALLY tainted: THE ENTIRE VPC, not a subnet
```

They made a typo. They tainted the VPC instead of the subnet.

### The Crisis

```bash
terraform plan

# Output (absolute horror):
#
# -/+ module.vpc.aws_vpc.this (tainted, forces replacement)
# -/+ module.vpc.aws_subnet.public[0] (forces replacement because vpc_id changed)
# -/+ module.vpc.aws_subnet.public[1] (forces replacement because vpc_id changed)
# -/+ module.vpc.aws_subnet.private[0] (forces replacement)
# -/+ module.vpc.aws_subnet.private[1] (forces replacement)
# -/+ module.vpc.aws_internet_gateway.this (forces replacement)
# -/+ module.vpc.aws_nat_gateway.this[0] (forces replacement)
# -/+ module.vpc.aws_nat_gateway.this[1] (forces replacement)
# -/+ module.vpc.aws_route_table.public (forces replacement)
# -/+ module.vpc.aws_route_table.private[0] (forces replacement)
# -   module.eks.aws_eks_cluster.this (depends on destroyed subnets)
# -   module.eks.aws_eks_node_group.workers (depends on destroyed cluster)
# ... every single resource that depends on the VPC ...
#
# Plan: 47 to add, 0 to change, 47 to destroy.
```

Terraform wants to destroy and recreate **everything**. The VPC is the root of the dependency tree. Taint the VPC and the entire infrastructure cascades.

If this plan had been applied, it would have:
1. Destroyed the EKS cluster (and all running workloads)
2. Destroyed all subnets, route tables, and NAT gateways
3. Destroyed all security groups
4. Attempted to recreate everything (which takes 20+ minutes for EKS alone)

### The Recovery

Fortunately, the engineer saw the plan output and did NOT apply. The fix:

```bash
# Untaint the VPC -- undo the mistake
terraform untaint module.vpc.aws_vpc.this

# Verify
terraform plan
# Output: No changes. Your infrastructure matches the configuration.
```

Crisis averted. But only because they **read the plan output**.

### Prevention: Lifecycle Rules

For critical resources that should never be accidentally destroyed, use lifecycle rules:

```hcl
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"

  lifecycle {
    prevent_destroy = true
  }

  tags = {
    Name = "production-vpc"
  }
}

resource "aws_eks_cluster" "main" {
  name    = "production"
  version = "1.28"

  lifecycle {
    prevent_destroy = true
  }
}
```

With `prevent_destroy = true`, Terraform will refuse to destroy the resource even if it is tainted:

```bash
terraform taint aws_vpc.main
terraform plan

# Error: Instance cannot be destroyed
# Resource aws_vpc.main has lifecycle.prevent_destroy set, but the plan
# calls for this resource to be destroyed.
```

### The Modern Alternative

In Terraform 1.5+, `terraform taint` is deprecated. Use the `-replace` flag instead, which is safer because it shows you the plan before doing anything:

```bash
# Old (dangerous -- taints without showing consequences):
terraform taint aws_subnet.public[0]
terraform plan   # Now you see the damage, but taint is already set

# New (safe -- shows plan WITH the replacement):
terraform plan -replace="aws_subnet.public[0]"
# You see exactly what will happen BEFORE committing to anything

terraform apply -replace="aws_subnet.public[0]"
# Only replaces if you confirm
```

### The Lessons

**Lesson 1**: `terraform taint` is a loaded gun pointed at your infrastructure. Use `-replace` instead.

**Lesson 2**: Always add `prevent_destroy = true` to VPCs, EKS clusters, databases, and any resource that would cause a cascade if destroyed.

**Lesson 3**: Never run `terraform apply` without reading every line of the plan. The plan is the last line of defense between you and catastrophe.

**Lesson 4**: In Terraform, dependencies cascade. Destroying a parent resource means destroying ALL of its children. Know your dependency tree.

---

## 7. War Story #6: The Secrets in State File Breach

### The Setup

A team stores their Terraform code in GitHub. They are careful about `.gitignore` for `.tfvars` files that contain secrets. But they missed something critical.

Their RDS database is defined like this:

```hcl
resource "aws_db_instance" "main" {
  identifier     = "production-db"
  engine         = "postgres"
  engine_version = "15.4"
  instance_class = "db.r5.large"
  username       = "admin"
  password       = "Sup3rS3cretP@ssw0rd!"  # "We'll fix this later"

  # ...
}
```

They know hardcoding the password is bad. But it is a Friday afternoon, and they want to get the PR merged before the weekend. "We'll rotate it Monday."

### The Crisis

Their `.gitignore` includes:

```
*.tfvars
.terraform/
```

But it does NOT include `terraform.tfstate`. The state file gets committed to Git.

The problem: **Terraform state files contain every attribute of every resource, including secrets in plain text.**

```json
// Inside terraform.tfstate (committed to Git):
{
  "type": "aws_db_instance",
  "name": "main",
  "attributes": {
    "identifier": "production-db",
    "username": "admin",
    "password": "Sup3rS3cretP@ssw0rd!",
    "endpoint": "production-db.abc123.us-east-1.rds.amazonaws.com",
    "port": 5432
  }
}
```

The repository is private, but 47 people have access. An intern is running `git log` and sees the state file in the history. They mention it in the engineering Slack channel.

The security team is alerted. Now it is an incident.

### The Investigation

The damage assessment:
- The password has been in the Git history for 3 weeks
- 47 engineers had read access to the repo
- The repository was private (never public), so external exposure is unlikely
- But Git history is permanent -- even deleting the file does not remove it from history
- The database is production, holding customer data

### The Emergency Response

```bash
# Step 1: IMMEDIATELY rotate the database password
# Do this in the AWS Console, NOT through Terraform
aws rds modify-db-instance \
  --db-instance-identifier production-db \
  --master-user-password "$(openssl rand -base64 32)" \
  --apply-immediately

# Step 2: Update all applications that use this password
# They need the new password from Secrets Manager, not from code

# Step 3: Remove state file from Git history (this is painful)
# Using git-filter-repo (preferred over filter-branch):
git filter-repo --path terraform.tfstate --invert-paths
git filter-repo --path terraform.tfstate.backup --invert-paths

# Step 4: Force push (everyone must re-clone)
git push --force --all

# Step 5: Move state to S3 (should have been there from the start)
terraform init -backend-config="bucket=secure-state-bucket" \
               -backend-config="key=production/terraform.tfstate"
```

### The Proper Way to Handle Secrets

**Option 1: Use AWS Secrets Manager and reference it**

```hcl
# Generate a random password
resource "random_password" "db_password" {
  length  = 32
  special = true
}

# Store it in Secrets Manager
resource "aws_secretsmanager_secret" "db_password" {
  name = "production/db/master-password"
}

resource "aws_secretsmanager_secret_version" "db_password" {
  secret_id     = aws_secretsmanager_secret.db_password.id
  secret_string = random_password.db_password.result
}

# Use it in the database
resource "aws_db_instance" "main" {
  identifier     = "production-db"
  engine         = "postgres"
  engine_version = "15.4"
  instance_class = "db.r5.large"
  username       = "admin"
  password       = random_password.db_password.result
}
```

NOTE: The password is still in state. But state is now in encrypted S3, not in Git. This is acceptable but not perfect.

**Option 2: RDS-managed credentials (best)**

```hcl
resource "aws_db_instance" "main" {
  identifier     = "production-db"
  engine         = "postgres"
  engine_version = "15.4"
  instance_class = "db.r5.large"
  username       = "admin"

  manage_master_user_password   = true                # AWS manages the password
  master_user_secret_kms_key_id = aws_kms_key.db.arn  # Encrypted with your KMS key
}
```

With this approach, AWS generates and rotates the password automatically. It never appears in Terraform state. Applications retrieve it from Secrets Manager at runtime.

**Option 3: External Secrets Operator for Kubernetes**

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: db-credentials
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: aws-secrets-manager
    kind: ClusterSecretStore
  target:
    name: db-credentials
  data:
    - secretKey: password
      remoteRef:
        key: production/db/master-password
```

### Your .gitignore Must Include

```gitignore
# Terraform
*.tfstate
*.tfstate.*
*.tfvars
*.tfvars.json
.terraform/
.terraform.lock.hcl
crash.log
crash.*.log
override.tf
override.tf.json
*_override.tf
*_override.tf.json
```

### The Lessons

**Lesson 1**: State files contain secrets in plain text. Always. Treat them as sensitive.

**Lesson 2**: Never store state in Git. Use remote backends with encryption.

**Lesson 3**: "We'll fix it Monday" is the most dangerous sentence in engineering.

**Lesson 4**: Use `manage_master_user_password = true` for RDS to keep credentials out of state entirely.

**Lesson 5**: Audit your `.gitignore` now. Not after the breach. Now.

---

## 8. War Story #7: The Cross-Region Replication Failure

### The Setup

A team manages infrastructure across two regions: `us-east-1` (primary) and `us-west-2` (disaster recovery). Their Terraform code uses a single provider:

```hcl
provider "aws" {
  region = var.region  # Defaults to "us-east-1"
}
```

One of the engineers is setting up the DR environment. They have an environment variable set from a previous debugging session:

```bash
# Forgotten from yesterday's debugging session:
export AWS_DEFAULT_REGION=us-west-2
```

### The Crisis

The engineer runs:

```bash
cd production-cluster/
terraform apply
```

Terraform creates the entire production EKS cluster -- all the VPCs, subnets, NAT gateways, EKS cluster, node groups -- in `us-west-2`. Not `us-east-1`.

They do not notice immediately because everything applies successfully. The outputs look normal. The cluster responds to kubectl commands.

Thirty minutes later, the application team deploys their services. Latency is terrible. Their database is in `us-east-1`, but the application is running in `us-west-2`. Every database query crosses the country.

```
+------------------------------+              +------------------------------+
|        us-west-2             |              |         us-east-1            |
|                              |   ~70ms per  |                              |
|  [EKS Cluster]  -------- query --------->  [RDS Database]               |
|  (accidentally created       |              |  (correct region)            |
|   here)                      |              |                              |
+------------------------------+              +------------------------------+
```

### The Fix: Provider Aliases and Region Validation

```hcl
# Explicit provider configuration with region validation
provider "aws" {
  region = "us-east-1"  # HARDCODED, not a variable

  # Prevent accidental deployment to wrong account
  allowed_account_ids = ["123456789012"]
}

# If you need multi-region, use explicit aliases
provider "aws" {
  alias  = "dr"
  region = "us-west-2"

  allowed_account_ids = ["123456789012"]
}

# Resources explicitly declare which provider to use
resource "aws_vpc" "primary" {
  provider   = aws           # us-east-1
  cidr_block = "10.0.0.0/16"
}

resource "aws_vpc" "dr" {
  provider   = aws.dr        # us-west-2
  cidr_block = "10.1.0.0/16"
}
```

### Additional Safety: Validation Blocks

```hcl
variable "environment" {
  type = string

  validation {
    condition     = contains(["staging", "production"], var.environment)
    error_message = "Environment must be 'staging' or 'production'."
  }
}

variable "region" {
  type    = string
  default = "us-east-1"

  validation {
    condition     = contains(["us-east-1", "us-west-2"], var.region)
    error_message = "Region must be us-east-1 (primary) or us-west-2 (DR only)."
  }
}

# Use a data source to verify you're in the right region
data "aws_region" "current" {}

resource "null_resource" "region_check" {
  count = data.aws_region.current.name != var.region ? 1 : 0

  provisioner "local-exec" {
    command = "echo 'ERROR: AWS region mismatch!' && exit 1"
  }
}
```

### The Lessons

**Lesson 1**: Hardcode the region in the provider block for production configurations. Do not use variables that can be overridden by environment variables.

**Lesson 2**: `AWS_DEFAULT_REGION` and `AWS_REGION` environment variables override the provider region. This is a feature that becomes a bug when you forget it is set.

**Lesson 3**: Use `allowed_account_ids` to prevent deploying to the wrong AWS account.

**Lesson 4**: When operating multi-region, use explicit provider aliases so every resource declares its region.

---

## 9. War Story #8: The Helm Release That Wouldn't Die

### The Setup

A team deploys the NGINX Ingress Controller using Terraform's Helm provider:

```hcl
resource "helm_release" "ingress_nginx" {
  name       = "ingress-nginx"
  repository = "https://kubernetes.github.io/ingress-nginx"
  chart      = "ingress-nginx"
  namespace  = "ingress-nginx"
  version    = "4.8.3"

  create_namespace = true

  set {
    name  = "controller.service.type"
    value = "LoadBalancer"
  }
}
```

During deployment, the network times out mid-install. The Helm release enters a limbo state.

### The Crisis

```bash
helm list -n ingress-nginx

# NAME            STATUS          CHART
# ingress-nginx   pending-install ingress-nginx-4.8.3
```

`pending-install`. Not `deployed`. Not `failed`. Pending.

The engineer tries to fix it with Terraform:

```bash
terraform apply

# Error: cannot re-use a name that is still in use
```

Terraform cannot install it because Helm thinks it is already being installed.

```bash
terraform destroy -target=helm_release.ingress_nginx

# Error: uninstallation completed with 1 error(s): timed out waiting
# for the condition
```

Terraform cannot destroy it because the release never fully installed, so there are orphaned resources that Helm cannot cleanly remove.

The engineer is stuck. Terraform cannot apply. Terraform cannot destroy. The release is undead.

### The Recovery: The Nuclear Option

```bash
# Step 1: Force-remove the Helm release from Helm's tracking
helm uninstall ingress-nginx -n ingress-nginx --no-hooks

# If that fails too:
kubectl delete secret -n ingress-nginx -l "owner=helm,name=ingress-nginx"

# Step 2: Clean up any orphaned Kubernetes resources
kubectl delete all -n ingress-nginx --all
kubectl delete namespace ingress-nginx

# Step 3: Remove from Terraform state (Terraform no longer tracks it)
terraform state rm helm_release.ingress_nginx

# Step 4: Verify clean state
terraform plan

# Output should show:
# + helm_release.ingress_nginx (will be created)

# Step 5: Re-apply cleanly
terraform apply
```

### Prevention: Timeouts and Atomic Configuration

```hcl
resource "helm_release" "ingress_nginx" {
  name       = "ingress-nginx"
  repository = "https://kubernetes.github.io/ingress-nginx"
  chart      = "ingress-nginx"
  namespace  = "ingress-nginx"
  version    = "4.8.3"

  create_namespace = true

  # Increase timeout for large charts
  timeout = 600  # 10 minutes (default is 5 minutes)

  # If install fails, automatically clean up
  atomic = true  # Rolls back on failure instead of leaving "pending-install"

  # Wait for all resources to be ready
  wait = true

  # Clean up on deletion
  cleanup_on_fail = true

  set {
    name  = "controller.service.type"
    value = "LoadBalancer"
  }
}
```

The key setting is `atomic = true`. With atomic installs, Helm automatically rolls back a failed installation instead of leaving it in a `pending-install` state. This single setting would have prevented the entire incident.

### The Lessons

**Lesson 1**: Always set `atomic = true` on Helm releases in Terraform. A stuck `pending-install` is far worse than a clean failure.

**Lesson 2**: Know the nuclear option: `helm uninstall` + `kubectl` cleanup + `terraform state rm`. You will need it eventually.

**Lesson 3**: Increase the `timeout` for charts that create LoadBalancers or PersistentVolumes. These resources can take several minutes to provision.

**Lesson 4**: Helm stores release state as Kubernetes secrets. If all else fails, deleting those secrets resets Helm's knowledge of the release.

---

## 10. War Story #9: The Autoscaler That Scaled to Infinity

### The Setup

A team configures their EKS node group with the Cluster Autoscaler. They write the Terraform quickly:

```hcl
resource "aws_eks_node_group" "workers" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "workers"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = module.vpc.private_subnets

  instance_types = ["m5.large"]

  scaling_config {
    desired_size = 3
    min_size     = 1
    max_size     = 999  # "Let's not limit it, autoscaler will figure it out"
  }
}
```

`max_size = 999`. The engineer's reasoning: "We don't want autoscaling to be blocked by an arbitrary limit. The autoscaler is smart enough to scale appropriately."

The autoscaler is not that smart.

### The Crisis

On a Friday night, Spot Instance interruptions hit their region. AWS reclaims a batch of Spot Instances. The Cluster Autoscaler detects that pods are unschedulable and begins requesting new nodes. But the new Spot Instances are also being reclaimed because of the regional capacity issue.

The autoscaler's logic:
1. Pods are pending. Need more nodes.
2. Request 5 new nodes.
3. 3 of those nodes get interrupted before pods schedule.
4. More pods are pending now. Need more nodes.
5. Request 10 new nodes.
6. Half get interrupted...
7. GOTO 1.

In 10 minutes, the autoscaler launched 200 nodes. Most were interrupted, but at any given moment, 40-60 were running.

```
Node count over time:

200 |                                     *
    |                                  *  *
150 |                               *  *  *
    |                            *  *  *  *
100 |                         *  *  *  *  *
    |                      *  *  *  *  *  *
 50 |                   *  *  *  *  *  *  *
    |                *  *  *  *  *  *  *  *
  3 | * * * * * * *  *  *  *  *  *  *  *  *
    +-------+-------+--+--+--+--+--+--+--+-->
    0       5       10 12 14 16 18 20 25 30 min

    Normal     ^-- Spot interruption cascade begins
```

The bill for those 200 nodes running for even 30 minutes: approximately $180. Not catastrophic. But the real damage was the cascading failures: the Kubernetes API server was overwhelmed by 200 nodes registering and deregistering, DNS resolution broke, and existing healthy pods started failing their liveness probes.

### The Fix

```bash
# Immediate triage: stop the autoscaler
kubectl scale deployment cluster-autoscaler -n kube-system --replicas=0

# Manually set node group to sane size
aws eks update-nodegroup-config \
  --cluster-name production \
  --nodegroup-name workers \
  --scaling-config minSize=2,maxSize=10,desiredSize=3
```

### The Proper Configuration

```hcl
resource "aws_eks_node_group" "workers" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "workers"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = module.vpc.private_subnets

  # Use On-Demand for baseline, Spot for burst
  instance_types = ["m5.large", "m5a.large", "m5d.large"]  # Multiple types for Spot
  capacity_type  = "ON_DEMAND"  # For baseline; use a separate group for Spot

  scaling_config {
    desired_size = 3
    min_size     = 2
    max_size     = 10  # Sane maximum: 3x your normal desired size
  }
}

# Separate node group for Spot with even more conservative limits
resource "aws_eks_node_group" "spot_workers" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "spot-workers"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = module.vpc.private_subnets

  instance_types = ["m5.large", "m5a.large", "m5d.large", "m4.large"]
  capacity_type  = "SPOT"

  scaling_config {
    desired_size = 0
    min_size     = 0
    max_size     = 5  # Spot is unpredictable; keep limits tight
  }
}
```

### Alarms That Would Have Caught This

```hcl
resource "aws_cloudwatch_metric_alarm" "node_count_high" {
  alarm_name          = "eks-node-count-abnormally-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "cluster_node_count"
  namespace           = "ContainerInsights"
  period              = 300
  statistic           = "Maximum"
  threshold           = 15  # Alert if more than 5x normal
  alarm_description   = "Node count exceeded safe threshold"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    ClusterName = aws_eks_cluster.main.name
  }
}

# Also set AWS Service Quotas to limit maximum EC2 instances
# This is your last line of defense
```

### The Lessons

**Lesson 1**: `max_size` is not a suggestion. It is a circuit breaker. Set it to a number that would still be fine if fully scaled.

**Lesson 2**: Separate On-Demand and Spot into different node groups with different limits.

**Lesson 3**: Spot Instance workloads need specific handling: multiple instance types, graceful termination handlers, and conservative autoscaling limits.

**Lesson 4**: Set CloudWatch alarms on node count. If your cluster suddenly has 10x the normal nodes, something is wrong.

**Lesson 5**: AWS Service Quotas are your absolute last line of defense against runaway scaling. Set them deliberately.

---

## 11. War Story #10: The DNS Propagation Nightmare

### The Setup

A team automates their entire stack with Terraform: EKS, ExternalDNS, cert-manager, and an Ingress controller. The dependency chain looks clean on paper:

```
Ingress (needs TLS cert) --> cert-manager (needs DNS for validation)
                                     --> ExternalDNS (creates DNS records)
                                          --> Route53 (hosted zone exists)
```

They deploy everything in one `terraform apply`.

### The Crisis

The deployment completes "successfully." Terraform exits with no errors. But the application is not reachable.

```bash
kubectl get certificate -n app
# NAME         READY   AGE
# app-cert     False   15m

kubectl describe certificate app-cert -n app
# Status:
#   Conditions:
#     Message: Waiting for DNS-01 challenge propagation:
#              DNS record for "_acme-challenge.app.company.com" not yet propagated
```

cert-manager is trying to validate the TLS certificate using a DNS-01 challenge. It creates a TXT record and waits for Let's Encrypt to verify it. But ExternalDNS has not finished creating the A record yet, and the TTL on the zone is 300 seconds (5 minutes).

The ordering problem:

```
What ACTUALLY happens:
  T+0s    Terraform creates ExternalDNS deployment
  T+0s    Terraform creates cert-manager deployment
  T+0s    Terraform creates Ingress resource
  T+5s    ExternalDNS pod starts, begins watching Ingress resources
  T+10s   cert-manager pod starts, sees certificate request
  T+15s   cert-manager creates ACME challenge TXT record
  T+20s   ExternalDNS creates A record for app.company.com
  T+20s   cert-manager asks Let's Encrypt to validate
  T+20s   Let's Encrypt queries DNS... record not propagated yet
  T+60s   Let's Encrypt retries... still not propagated (TTL hasn't expired)
  T+300s  TTL expires, record propagates
  T+300s  cert-manager retries... but ACME order has expired
  T+300s  cert-manager creates NEW order... new TTL wait begins
  T+600s  Stuck in a loop. Certificate never becomes Ready.
```

### The Fix: Proper Sequencing

**Step 1: Lower the TTL before deployment**

```hcl
resource "aws_route53_record" "app" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "app.company.com"
  type    = "A"
  ttl     = 60  # Low TTL during initial setup (raise later for caching)

  records = [aws_lb.ingress.dns_name]
}
```

**Step 2: Use Terraform dependencies to enforce ordering**

```hcl
# Phase 1: DNS and ExternalDNS must be ready first
resource "helm_release" "external_dns" {
  name       = "external-dns"
  repository = "https://kubernetes-sigs.github.io/external-dns"
  chart      = "external-dns"
  namespace  = "external-dns"
  version    = "1.14.3"

  # ...configuration...
}

# Phase 2: cert-manager depends on ExternalDNS being ready
resource "helm_release" "cert_manager" {
  name       = "cert-manager"
  repository = "https://charts.jetstack.io"
  chart      = "cert-manager"
  namespace  = "cert-manager"
  version    = "1.13.3"

  depends_on = [helm_release.external_dns]

  set {
    name  = "installCRDs"
    value = "true"
  }
}

# Phase 3: Create the ClusterIssuer after cert-manager CRDs exist
resource "kubectl_manifest" "cluster_issuer" {
  yaml_body = <<-EOF
    apiVersion: cert-manager.io/v1
    kind: ClusterIssuer
    metadata:
      name: letsencrypt-prod
    spec:
      acme:
        server: https://acme-v02.api.letsencrypt.org/directory
        email: ops@company.com
        privateKeySecretRef:
          name: letsencrypt-prod
        solvers:
          - dns01:
              route53:
                region: us-east-1
                hostedZoneID: ${aws_route53_zone.main.zone_id}
  EOF

  depends_on = [helm_release.cert_manager]
}

# Phase 4: Ingress LAST, after everything else is ready
resource "kubectl_manifest" "ingress" {
  yaml_body = <<-EOF
    apiVersion: networking.k8s.io/v1
    kind: Ingress
    metadata:
      name: app
      namespace: app
      annotations:
        cert-manager.io/cluster-issuer: letsencrypt-prod
        external-dns.alpha.kubernetes.io/hostname: app.company.com
    spec:
      tls:
        - hosts:
            - app.company.com
          secretName: app-cert
      rules:
        - host: app.company.com
          http:
            paths:
              - path: /
                pathType: Prefix
                backend:
                  service:
                    name: app
                    port:
                      number: 80
  EOF

  depends_on = [
    kubectl_manifest.cluster_issuer,
    helm_release.external_dns,
  ]
}
```

**Step 3: Use a staging issuer for testing**

```yaml
# Use Let's Encrypt staging first to avoid rate limits
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-staging
spec:
  acme:
    server: https://acme-staging-v02.api.letsencrypt.org/directory
    # ... rest of config
```

Let's Encrypt production has strict rate limits. If your certificate keeps failing and retrying, you will hit those limits and be locked out for a week. Always test with staging first.

### The Lessons

**Lesson 1**: DNS propagation is not instant. TTLs, caching, and propagation delays mean a record you just created might not be visible for minutes.

**Lesson 2**: cert-manager, ExternalDNS, and Ingress controllers have a specific ordering dependency. Respect it with `depends_on`.

**Lesson 3**: Use low TTLs (60 seconds) during initial deployment. Raise them later once everything is stable.

**Lesson 4**: Always test with Let's Encrypt staging before production to avoid rate limiting.

---

## 12. Essential Debugging Commands

### Terraform Debugging Commands

```bash
# ------------------------------------------------------------------
# STATE INSPECTION
# ------------------------------------------------------------------

# List everything Terraform manages
terraform state list

# Show details of a specific resource
terraform state show module.vpc.aws_vpc.this

# Show the entire state (WARNING: contains secrets)
terraform state pull

# Find a resource in state by partial name
terraform state list | grep "security_group"

# ------------------------------------------------------------------
# PLAN AND DIFF ANALYSIS
# ------------------------------------------------------------------

# Detailed plan with full output
terraform plan -out=tfplan
terraform show -json tfplan | jq '.'

# Show only resources that will be destroyed
terraform plan -json | jq 'select(.type == "planned_change") |
  select(.change.actions[] == "delete")'

# Target a specific resource for planning
terraform plan -target=module.eks.aws_eks_cluster.this

# ------------------------------------------------------------------
# DEBUGGING
# ------------------------------------------------------------------

# Enable verbose logging
TF_LOG=DEBUG terraform plan 2>debug.log

# Just provider-level logs
TF_LOG=TRACE TF_LOG_PROVIDER=DEBUG terraform plan 2>provider.log

# Interactive expression testing
terraform console
> module.vpc.private_subnets
> length(var.availability_zones)
> cidrsubnet("10.0.0.0/16", 8, 1)

# ------------------------------------------------------------------
# DEPENDENCY ANALYSIS
# ------------------------------------------------------------------

# Generate dependency graph (requires graphviz)
terraform graph | dot -Tsvg > graph.svg

# Show graph for destroy operations (different dependencies)
terraform graph -type=destroy | dot -Tsvg > destroy-graph.svg

# ------------------------------------------------------------------
# STATE SURGERY (use with extreme caution)
# ------------------------------------------------------------------

# Move a resource to a different address (rename refactoring)
terraform state mv aws_instance.old_name aws_instance.new_name

# Remove a resource from state (Terraform forgets it, resource still exists)
terraform state rm aws_instance.problematic

# Import an existing resource into state
terraform import aws_instance.example i-1234567890abcdef0
```

### kubectl Commands for EKS Debugging

```bash
# ------------------------------------------------------------------
# CLUSTER HEALTH
# ------------------------------------------------------------------

# Are all nodes healthy?
kubectl get nodes -o wide
kubectl describe node <node-name> | grep -A 5 "Conditions"

# Node resource utilization
kubectl top nodes
kubectl top pods --all-namespaces --sort-by=memory

# ------------------------------------------------------------------
# POD DEBUGGING
# ------------------------------------------------------------------

# Why is a pod not starting?
kubectl describe pod <pod-name> -n <namespace>

# Common events to look for in describe output:
#   FailedScheduling    = No node has enough resources
#   ImagePullBackOff    = Cannot pull container image
#   CrashLoopBackOff    = Container starts and immediately crashes
#   Pending             = Waiting for resources or node assignment

# Get logs from a crashed container
kubectl logs <pod-name> -n <namespace> --previous

# Stream logs in real time
kubectl logs -f <pod-name> -n <namespace>

# Execute into a running pod for debugging
kubectl exec -it <pod-name> -n <namespace> -- /bin/sh

# ------------------------------------------------------------------
# NETWORKING
# ------------------------------------------------------------------

# Check DNS resolution inside the cluster
kubectl run debug --rm -it --image=busybox -- nslookup kubernetes.default

# Check if a service is reachable
kubectl run debug --rm -it --image=busybox -- wget -qO- http://service-name.namespace.svc.cluster.local

# List all endpoints (are pods behind the service?)
kubectl get endpoints <service-name> -n <namespace>

# ------------------------------------------------------------------
# RBAC AND PERMISSIONS
# ------------------------------------------------------------------

# Can this service account do this action?
kubectl auth can-i get pods --as=system:serviceaccount:namespace:sa-name

# Who has cluster-admin?
kubectl get clusterrolebindings -o json | \
  jq '.items[] | select(.roleRef.name=="cluster-admin") | .subjects'
```

### AWS CLI Commands for Troubleshooting

```bash
# ------------------------------------------------------------------
# EKS CLUSTER
# ------------------------------------------------------------------

# Cluster status and details
aws eks describe-cluster --name production --query 'cluster.status'

# Check cluster logging (is it enabled?)
aws eks describe-cluster --name production \
  --query 'cluster.logging.clusterLogging'

# List node groups and their status
aws eks list-nodegroups --cluster-name production
aws eks describe-nodegroup --cluster-name production \
  --nodegroup-name workers --query 'nodegroup.status'

# ------------------------------------------------------------------
# VPC AND NETWORKING
# ------------------------------------------------------------------

# Check NAT Gateway status
aws ec2 describe-nat-gateways --filter "Name=vpc-id,Values=vpc-xxx" \
  --query 'NatGateways[].{Id:NatGatewayId,State:State,SubnetId:SubnetId}'

# Check route tables
aws ec2 describe-route-tables --filters "Name=vpc-id,Values=vpc-xxx" \
  --query 'RouteTables[].{Id:RouteTableId,Routes:Routes}'

# Verify security group rules
aws ec2 describe-security-groups --group-ids sg-xxx \
  --query 'SecurityGroups[].{Ingress:IpPermissions,Egress:IpPermissionsEgress}'

# ------------------------------------------------------------------
# IAM AND PERMISSIONS
# ------------------------------------------------------------------

# Who am I? (check current credentials)
aws sts get-caller-identity

# Check an IAM role's policies
aws iam list-attached-role-policies --role-name eks-node-role
aws iam list-role-policies --role-name eks-node-role

# Simulate whether a role can perform an action
aws iam simulate-principal-policy \
  --policy-source-arn arn:aws:iam::123456789012:role/eks-node-role \
  --action-names ec2:DescribeInstances

# ------------------------------------------------------------------
# CLOUDWATCH LOGS
# ------------------------------------------------------------------

# Tail EKS control plane logs
aws logs tail /aws/eks/production/cluster --follow --since 1h

# Search for specific errors in logs
aws logs filter-log-events \
  --log-group-name /aws/eks/production/cluster \
  --filter-pattern "ERROR" \
  --start-time $(date -d '1 hour ago' +%s000)
```

### The Complete Debugging Cheat Sheet

```
+------------------------------------------------------------------+
|                  DEBUGGING DECISION TREE                          |
|                                                                   |
|  Symptom                          First Command                   |
|  ------                           -------------                   |
|  terraform plan shows drift  -->  terraform state show <resource> |
|  terraform apply error       -->  TF_LOG=DEBUG terraform apply    |
|  state is corrupted          -->  terraform state pull > backup   |
|  resource won't delete       -->  terraform state rm + manual     |
|  cycle error                 -->  terraform graph | dot -Tsvg     |
|                                                                   |
|  pods not starting           -->  kubectl describe pod <name>     |
|  pods crashing               -->  kubectl logs <pod> --previous   |
|  service unreachable         -->  kubectl get endpoints <svc>     |
|  nodes not ready             -->  kubectl describe node <name>    |
|  RBAC denied                 -->  kubectl auth can-i <verb> <res> |
|                                                                   |
|  network connectivity        -->  aws ec2 describe-route-tables   |
|  IAM issues                  -->  aws sts get-caller-identity     |
|  cluster unreachable         -->  aws eks describe-cluster        |
|  billing surprise            -->  aws ce get-cost-and-usage       |
+------------------------------------------------------------------+
```

---

## 13. The Post-Mortem Template

### Why Post-Mortems Matter

Every war story in this document came from a team that did not write post-mortems for previous incidents. They fixed the immediate problem and moved on. Six months later, a different engineer hit the same problem.

A post-mortem is not a blame document. It is an investment in your team's future. Write it while the incident is fresh, or you will forget the critical details that prevent the next one.

### The Blameless Culture

```
WRONG (blame culture):
  "Engineer X accidentally deleted the state file because they were
   careless. They should have been more careful."

  Result: Engineers hide mistakes. Problems recur. Trust erodes.

RIGHT (blameless culture):
  "The state file was deleted because our storage system allowed a
   single rm command to destroy critical data without confirmation
   or backup. The system should be designed so that this mistake
   is either impossible or immediately recoverable."

  Result: Engineers report mistakes early. Systems improve. Trust grows.
```

The core principle: **Humans make mistakes. Systems should make those mistakes safe.**

### Post-Mortem Template

```markdown
# Incident Post-Mortem: [Title]

## Metadata
- **Date of incident**: YYYY-MM-DD
- **Duration**: X hours Y minutes
- **Severity**: SEV-1 / SEV-2 / SEV-3
- **Author**: [Name]
- **Reviewers**: [Names]

## Summary
[2-3 sentences: what happened, what was the impact, how was it resolved]

## Timeline (all times in UTC)
- HH:MM - First alert / detection
- HH:MM - Team assembled
- HH:MM - Root cause identified
- HH:MM - Fix applied
- HH:MM - Service restored
- HH:MM - All-clear declared

## Impact
- **Users affected**: [number or percentage]
- **Revenue impact**: [estimate if applicable]
- **Data loss**: [yes/no, details]
- **Duration of impact**: [time]

## Root Cause
[Detailed technical explanation of WHY this happened. Not WHO -- WHY.]

## The 5 Whys
1. Why did [symptom] happen? Because [X].
2. Why did [X] happen? Because [Y].
3. Why did [Y] happen? Because [Z].
4. Why did [Z] happen? Because [process gap].
5. Why does [process gap] exist? Because [root cause].

## What Went Well
- [Things that helped during the incident]
- [Processes that worked]
- [Tools that were useful]

## What Went Wrong
- [Things that made the incident worse]
- [Missing tools or processes]
- [Communication gaps]

## Action Items
| Action | Owner | Priority | Due Date | Status |
|--------|-------|----------|----------|--------|
| [Specific action] | [Name] | P0/P1/P2 | YYYY-MM-DD | Open |
| [Specific action] | [Name] | P0/P1/P2 | YYYY-MM-DD | Open |

## Lessons Learned
[What should the broader team take away from this incident?]
```

### Post-Mortem Best Practices

1. **Write it within 48 hours.** Memory fades fast.
2. **Include the timeline with timestamps.** Reconstruct from Slack, PagerDuty, and CloudWatch.
3. **No blame.** If someone's name appears, it should be in the context of their heroic debugging, not their mistake.
4. **Action items must have owners and due dates.** "We should fix this" is not an action item. "Alice will add S3 versioning to the state bucket by March 15" is.
5. **Review as a team.** The post-mortem review meeting is where the real learning happens.
6. **Publish broadly.** Other teams will learn from your pain. That is the whole point.

---

## 14. Test Yourself: Debugging Scenarios

These scenarios are designed to test your debugging instincts. For each one, think about: What would you do FIRST? What is your hypothesis? How would you confirm it?

### Scenario 1: The Vanishing Pods

**Situation**: You deploy a new version of your application. The pods start, run for exactly 30 seconds, then get killed and restarted. `kubectl get pods` shows:

```
NAME                    READY   STATUS             RESTARTS   AGE
api-7d8f9c6b5-x2k4p    0/1     CrashLoopBackOff   5          8m
api-7d8f9c6b5-m9n2r    0/1     CrashLoopBackOff   5          8m
```

**Questions to consider**:
- What is the first command you run?
- What could cause a container to die at exactly 30 seconds?
- How do you distinguish between an application crash and an OOMKill?

**Debugging path**:
```bash
# Step 1: Check the previous container's logs
kubectl logs api-7d8f9c6b5-x2k4p --previous

# Step 2: Check the pod description for OOMKilled
kubectl describe pod api-7d8f9c6b5-x2k4p | grep -A 3 "Last State"

# Step 3: If OOMKilled, check resource limits
kubectl get pod api-7d8f9c6b5-x2k4p -o jsonpath='{.spec.containers[0].resources}'

# Step 4: If not OOMKilled, check liveness probe
kubectl get pod api-7d8f9c6b5-x2k4p -o jsonpath='{.spec.containers[0].livenessProbe}'
```

**Most likely cause**: The liveness probe has `initialDelaySeconds: 10` and `timeoutSeconds: 1`, but the application takes 35 seconds to start. The liveness probe kills the container before it finishes starting. Fix: increase `initialDelaySeconds` or add a `startupProbe`.

---

### Scenario 2: Terraform Plan Shows 47 Changes on Monday

**Situation**: Nobody touched the Terraform code over the weekend. On Monday morning, `terraform plan` shows 47 resources to change. All of them are tag changes.

```
~ tags = {
    - "last_updated" = "2026-03-13" -> null
    + "last_updated" = "2026-03-16"
  }
```

**Questions to consider**:
- What could change tags without anyone modifying Terraform code?
- How do you find out what is modifying your infrastructure?

**Debugging path**:
```bash
# Step 1: Check if there is a tag policy or AWS Config rule
aws organizations list-policies --filter TAG_POLICY

# Step 2: Check CloudTrail for who modified the tags
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=CreateTags \
  --start-time 2026-03-13T00:00:00Z

# Step 3: Look for Lambda functions or automation that auto-tag
aws lambda list-functions --query 'Functions[?contains(FunctionName, `tag`)]'
```

**Most likely cause**: An AWS Config rule or a Lambda function is automatically updating tags outside of Terraform. Fix: either remove the external automation or add `ignore_changes` in Terraform for those tags:

```hcl
lifecycle {
  ignore_changes = [tags["last_updated"]]
}
```

---

### Scenario 3: kubectl Works, Terraform Does Not

**Situation**: You can run `kubectl get nodes` and see your cluster. But `terraform plan` gives:

```
Error: Kubernetes cluster unreachable: invalid configuration:
no configuration has been provided
```

**Questions to consider**:
- What does Terraform use to authenticate to Kubernetes?
- What does kubectl use?
- Why would one work and not the other?

**Debugging path**:
```bash
# Step 1: Check what kubectl is using
kubectl config view --minify

# Step 2: Check what Terraform's kubernetes provider is configured to use
grep -A 10 'provider "kubernetes"' *.tf

# Step 3: Check if the EKS token is expired
aws eks get-token --cluster-name production

# Step 4: Verify the kubeconfig that Terraform is referencing exists
ls -la ~/.kube/config
```

**Most likely cause**: kubectl uses `~/.kube/config` which was configured by `aws eks update-kubeconfig`. Terraform's kubernetes provider is configured to use the `exec` block with `aws eks get-token`, but the AWS credentials it uses (possibly a different profile or role) have expired or do not have EKS permissions.

---

### Scenario 4: Apply Succeeds but Nothing Changes in AWS

**Situation**: You added a new security group rule in Terraform. `terraform apply` says "Apply complete! Resources: 1 added." But when you check AWS, the security group does not have the new rule.

**Questions to consider**:
- Can Terraform report success but the resource not actually exist?
- What is the first thing you check?

**Debugging path**:
```bash
# Step 1: Check if the resource is in state
terraform state show aws_security_group_rule.new_rule

# Step 2: Check if you are looking at the right security group
terraform state show aws_security_group_rule.new_rule | grep security_group_id

# Step 3: Check if you are in the right AWS account/region
aws sts get-caller-identity
aws configure get region

# Step 4: Check the security group in AWS
aws ec2 describe-security-groups --group-ids sg-xxx
```

**Most likely cause**: You are checking the wrong security group in the AWS Console, or you are logged into a different AWS account/region in the Console than where Terraform applied the change. Alternatively, the security group rule was created but was immediately deleted by an AWS Config remediation rule that enforces security group standards.

---

### Scenario 5: The Deadly Terraform Destroy

**Situation**: You are trying to destroy a dev environment. `terraform destroy` has been running for 35 minutes and is stuck on:

```
module.eks.aws_eks_cluster.this: Still destroying... [35m elapsed]
```

**Questions to consider**:
- Why would an EKS cluster take so long to delete?
- What could be blocking the deletion?
- Should you cancel the command?

**Debugging path**:
```bash
# In a SEPARATE terminal (do not cancel the running destroy):

# Step 1: Check if there are still node groups
aws eks list-nodegroups --cluster-name dev-cluster

# Step 2: Check if there are any Fargate profiles
aws eks list-fargate-profiles --cluster-name dev-cluster

# Step 3: Check if there are load balancers in the VPC
aws elbv2 describe-load-balancers --query \
  'LoadBalancers[?VpcId==`vpc-xxx`].{ARN:LoadBalancerArn,State:State}'

# Step 4: Check for ENIs blocking deletion
aws ec2 describe-network-interfaces \
  --filters "Name=vpc-id,Values=vpc-xxx" \
  --query 'NetworkInterfaces[?Status==`in-use`].{Id:NetworkInterfaceId,Desc:Description}'
```

**Most likely cause**: Kubernetes LoadBalancer services created AWS ELBs that are not managed by Terraform. These ELBs have Elastic Network Interfaces (ENIs) attached to the VPC subnets. EKS cannot delete the cluster until those ENIs are released, but the ENIs cannot be released until the ELBs are deleted. Fix: delete all LoadBalancer services in Kubernetes first (`kubectl delete svc --all-namespaces -l type=LoadBalancer`), then let the cloud controller clean up the ELBs, then the EKS destroy will proceed.

---

## Final Words

Every war story in this document has a common thread: **the failure was preventable**. Not with heroics. Not with genius. With boring, systematic practices:

- Remote state with versioning
- Reading plan output carefully
- Billing alarms set on day one
- Lifecycle rules on critical resources
- Post-mortems that lead to action items

The best infrastructure engineers are not the ones who never break anything. They are the ones who build systems where breakage is either impossible or immediately recoverable. They have seen the war stories. They have written the post-mortems. And they have put the guardrails in place.

Your job is not to be perfect. Your job is to make the system resilient to imperfection.

---

> **Next**: Continue to the next module in the series, where we build on these lessons with CI/CD pipelines and automated guardrails that catch these problems before they reach production.
