# 09 - Visual Explanations: Making Complex Infrastructure Intuitive

> **Goal**: Understand every major concept in this project through diagrams, analogies, and visual mental models. If a picture is worth a thousand words, this document is worth fourteen thousand.

---

## Table of Contents

1. [How Terraform Works - The Complete Picture](#1-how-terraform-works---the-complete-picture)
2. [The Terraform Lifecycle - Visual Flow](#2-the-terraform-lifecycle---visual-flow)
3. [Dependency Graph Visualization](#3-dependency-graph-visualization)
4. [State File - The Mental Model](#4-state-file---the-mental-model)
5. [VPC Architecture - The Complete Picture](#5-vpc-architecture---the-complete-picture)
6. [EKS Architecture - Visual Deep Dive](#6-eks-architecture---visual-deep-dive)
7. [Networking Flow - From User to Pod](#7-networking-flow---from-user-to-pod)
8. [IAM and IRSA - Visual Explanation](#8-iam-and-irsa---visual-explanation)
9. [CI/CD Pipeline Visualization](#9-cicd-pipeline-visualization)
10. [Scaling Visualizations](#10-scaling-visualizations)
11. [Cost Flow Diagram](#11-cost-flow-diagram)
12. [Security Layers - The Onion Model](#12-security-layers---the-onion-model)
13. [The Complete EKS Production Stack](#13-the-complete-eks-production-stack)
14. [Explain Like I'm 5 (ELI5) Section](#14-explain-like-im-5-eli5-section)

---

## 1. How Terraform Works - The Complete Picture

### The End-to-End Flow

Every time you run Terraform, this is what actually happens:

```
 YOU (Developer)
  |
  |  Write .tf files
  v
┌─────────────────────────────┐
│      Terraform CLI           │
│                              │
│  1. Parse HCL files         │
│  2. Build dependency graph   │
│  3. Read current state       │
│  4. Calculate diff           │
│  5. Generate execution plan  │
└──────────────┬───────────────┘
               |
               |  API calls via provider
               v
┌─────────────────────────────┐
│     AWS Provider Plugin      │
│                              │
│  Translates Terraform        │
│  operations into AWS API     │
│  calls (Create, Read,        │
│  Update, Delete)             │
└──────────────┬───────────────┘
               |
               |  HTTPS REST API calls
               v
┌─────────────────────────────┐
│       AWS API Endpoints      │
│                              │
│  ec2.amazonaws.com           │
│  eks.amazonaws.com           │
│  iam.amazonaws.com           │
│  s3.amazonaws.com            │
│  ...                         │
└──────────────┬───────────────┘
               |
               |  Creates/modifies
               v
┌─────────────────────────────┐
│    Real AWS Resources        │
│                              │
│  VPCs, Subnets, EKS         │
│  Clusters, IAM Roles,        │
│  Security Groups, etc.       │
└──────────────┬───────────────┘
               |
               |  Resource IDs, ARNs, IPs
               v
┌─────────────────────────────┐
│     Terraform State File     │
│                              │
│  Records what was created,   │
│  their IDs, attributes,      │
│  and dependencies.           │
│  (terraform.tfstate)         │
└─────────────────────────────┘
```

### The "Architect with Blueprints" Analogy - Expanded

Think of building a house. Here is every role mapped:

```
Real World                          Terraform World
─────────────────────────────────────────────────────────────────
Architect                           You (the developer)
Blueprints                          .tf files (your code)
General Contractor                  Terraform CLI
Specialized subcontractors          Providers (AWS, Azure, GCP)
  - Electrician                       - aws_security_group
  - Plumber                           - aws_subnet
  - Roofer                            - aws_eks_cluster
Building permits office             AWS API
The actual house                    Real cloud resources
Photograph of the finished house    terraform.tfstate
Building inspector                  terraform plan
```

**Why this analogy works so well:**

- The architect (you) draws blueprints (.tf files) describing the desired house.
- The general contractor (Terraform) reads the blueprints, figures out what order
  to build things (you cannot install electricity before the walls exist), and
  hires the right subcontractors (providers).
- Each subcontractor (provider) knows how to talk to the building permits office
  (AWS API) and do the actual construction.
- After construction, someone takes a photograph (state file) so that next time
  you want to make changes, the contractor can compare the photo to the new
  blueprints and figure out what changed.

### State as the "Photograph of Your House"

```
  ┌───────────────────────────────────────────────────────────┐
  │                  terraform.tfstate                         │
  │                                                            │
  │  Think of this as a detailed photograph:                   │
  │                                                            │
  │  "The house at 123 Main St has:                            │
  │    - 3 bedrooms (resource: aws_instance x 3)              │
  │    - 2 bathrooms (resource: aws_subnet x 2)               │
  │    - 1 garage (resource: aws_nat_gateway x 1)             │
  │    - Blue paint (attribute: tags = {color: blue})         │
  │    - Built on Lot #vpc-0a1b2c3d (attribute: vpc_id)"     │
  │                                                            │
  │  Without this photograph, Terraform cannot know what       │
  │  already exists. It would try to build a second house      │
  │  instead of renovating the first one.                      │
  └───────────────────────────────────────────────────────────┘
```

---

## 2. The Terraform Lifecycle - Visual Flow

### The Complete Flowchart

```
┌──────────────┐
│  Write Code  │    You edit .tf files
│  (main.tf)   │
└──────┬───────┘
       |
       v
┌──────────────┐     ┌──────────────────────────────────┐
│ terraform    │     │ Downloads providers (aws, helm)   │
│ init         │────>│ Initializes backend (S3, local)   │
│              │     │ Downloads modules                 │
└──────┬───────┘     └──────────────────────────────────┘
       |
       |  Success?
       |
    NO |──────────> Fix: check provider versions, backend config,
       |            network connectivity, credentials
       v
┌──────────────┐     ┌──────────────────────────────────┐
│ terraform    │     │ 1. Read current state             │
│ validate     │────>│ 2. Check HCL syntax              │
│              │     │ 3. Verify type constraints         │
└──────┬───────┘     └──────────────────────────────────┘
       |
       |  Valid?
       |
    NO |──────────> Fix: syntax errors, missing variables,
       |            type mismatches, invalid references
       v
┌──────────────┐     ┌──────────────────────────────────┐
│ terraform    │     │ 1. Refresh state (read real AWS)  │
│ plan         │────>│ 2. Compare desired vs actual      │
│              │     │ 3. Generate change set            │
│              │     │ 4. Show: +create ~update -destroy │
└──────┬───────┘     └──────────────────────────────────┘
       |
       |  Changes look correct?
       |
    NO |──────────> Fix: adjust code, check for unintended
       |            destroys, verify conditional logic
       v
┌──────────────┐     ┌──────────────────────────────────┐
│ terraform    │     │ 1. Acquire state lock             │
│ apply        │────>│ 2. Execute changes in DAG order   │
│              │     │ 3. Make real AWS API calls         │
│              │     │ 4. Update state file               │
│              │     │ 5. Release state lock              │
└──────┬───────┘     └──────────────────────────────────┘
       |
       |  Success?
       |
    NO |──────────> Partial state update occurred!
       |            Resources may be half-created.
       |            Run plan again to see current state.
       |            Fix the issue, then apply again.
       |
       v
┌──────────────┐
│   DONE       │    State file is up to date.
│              │    Infrastructure matches code.
└──────────────┘
```

### What Happens at Each Step - Simplified

| Step       | What Happens                              | Can Fail Because                        |
|------------|-------------------------------------------|-----------------------------------------|
| `init`     | Download dependencies, set up backend     | Bad internet, wrong provider version    |
| `validate` | Check syntax and types                    | Typos, missing variables                |
| `plan`     | Dry run - compare code to reality         | API auth, invalid resource config       |
| `apply`    | Actually create/change/destroy resources  | Rate limits, permission denied, quotas  |

---

## 3. Dependency Graph Visualization

### Simple 3-Resource Graph

When you write this code:

```hcl
resource "aws_vpc" "main"     { cidr_block = "10.0.0.0/16" }
resource "aws_subnet" "web"   { vpc_id = aws_vpc.main.id }
resource "aws_instance" "app" { subnet_id = aws_subnet.web.id }
```

Terraform builds this graph:

```
        ┌───────────────┐
        │   aws_vpc     │    Created FIRST (no dependencies)
        │   "main"      │
        └───────┬───────┘
                |
                | vpc_id
                v
        ┌───────────────┐
        │  aws_subnet   │    Created SECOND (needs VPC ID)
        │   "web"       │
        └───────┬───────┘
                |
                | subnet_id
                v
        ┌───────────────┐
        │ aws_instance  │    Created THIRD (needs Subnet ID)
        │   "app"       │
        └───────────────┘

   Destroy order is the REVERSE: instance -> subnet -> vpc
```

### Complex Production Graph (Our EKS Project)

```
                           ┌───────────────┐
                           │   aws_vpc     │
                           │   "main"      │
                           └───────┬───────┘
                                   |
                    ┌──────────────┼──────────────┐
                    |              |              |
                    v              v              v
            ┌──────────┐  ┌──────────┐  ┌──────────────┐
            │ Public   │  │ Private  │  │ Database     │
            │ Subnets  │  │ Subnets  │  │ Subnets      │
            │ (x3)     │  │ (x3)     │  │ (x3)         │
            └────┬─────┘  └────┬─────┘  └──────────────┘
                 |              |
                 v              v
         ┌────────────┐  ┌─────────────┐
         │ Internet   │  │ NAT         │
         │ Gateway    │  │ Gateways    │
         └────────────┘  └─────┬───────┘
                               |
              ┌────────────────┼────────────────┐
              |                |                |
              v                v                v
      ┌──────────────┐ ┌─────────────┐ ┌──────────────┐
      │ EKS Cluster  │ │ IAM Roles   │ │ Security     │
      │              │ │ (IRSA)      │ │ Groups       │
      └──────┬───────┘ └──────┬──────┘ └──────────────┘
             |                |
             v                v
      ┌──────────────┐ ┌─────────────┐
      │ Node Groups  │ │ OIDC        │
      │ (Managed)    │ │ Provider    │
      └──────┬───────┘ └─────────────┘
             |
      ┌──────┼──────────────────┐
      |      |                  |
      v      v                  v
 ┌────────┐ ┌──────────┐ ┌───────────────┐
 │CoreDNS │ │AWS LB    │ │Cluster        │
 │        │ │Controller│ │Autoscaler     │
 └────────┘ └──────────┘ └───────────────┘
```

### Parallel Execution Visualization

Terraform does NOT create everything one at a time. Independent resources run in parallel:

```
Timeline ─────────────────────────────────────────────────>

Thread 1: ████ aws_vpc ████
                            ████ aws_subnet_a ████
                                                   ███ aws_eks ████████████
Thread 2:                   ████ aws_subnet_b ████
                                                   ███ node_group_a ██████
Thread 3:                   ████ aws_subnet_c ████
                                                   ███ node_group_b ██████
Thread 4: ████ aws_iam_role_cluster ████
Thread 5: ████ aws_iam_role_node ████
Thread 6:                                                ███ coredns_addon █
Thread 7:                                                ███ lb_controller █

           |                |                      |                       |
           t=0              t=1                    t=2                     t=3
           VPC + IAM        Subnets                EKS + Nodes            Add-ons
           (parallel)       (parallel,             (parallel,             (parallel,
                            wait for VPC)          wait for subnets)      wait for EKS)
```

**Key insight**: Terraform runs up to 10 operations in parallel by default (configurable
with `-parallelism=N`). Resources with no dependency between them execute simultaneously.

### How to Read `terraform graph` Output

Run `terraform graph | dot -Tpng > graph.png` to generate a visual graph.

The output is in DOT format:

```
digraph {
    "aws_vpc.main"           ->  "aws_subnet.public"
    "aws_subnet.public"      ->  "aws_instance.web"
    "aws_iam_role.cluster"   ->  "aws_eks_cluster.main"
    "aws_eks_cluster.main"   ->  "aws_eks_node_group.workers"
}
```

Reading rules:
- Arrow means "must be created before"
- Nodes with no incoming arrows can be created first (and in parallel)
- Nodes with no outgoing arrows are "leaf" resources (created last)
- The longest path through the graph determines minimum apply time

---

## 4. State File - The Mental Model

### The Bank Ledger Analogy

Your Terraform state is like a bank ledger. Every transaction (resource creation,
modification, deletion) is recorded so you always know the current balance.

```
┌─────────────────────────────────────────────────────────────────┐
│                    TERRAFORM STATE LEDGER                        │
├────────┬──────────────────────┬───────────────┬─────────────────┤
│ Entry  │ Resource             │ ID            │ Key Attributes  │
├────────┼──────────────────────┼───────────────┼─────────────────┤
│ 001    │ aws_vpc.main         │ vpc-0a1b2c3d  │ cidr=10.0.0.0/16│
│ 002    │ aws_subnet.public_a  │ subnet-1a2b3c │ az=us-east-1a   │
│ 003    │ aws_subnet.public_b  │ subnet-4d5e6f │ az=us-east-1b   │
│ 004    │ aws_subnet.private_a │ subnet-7g8h9i │ az=us-east-1a   │
│ 005    │ aws_eks_cluster.main │ my-cluster    │ version=1.28    │
│ 006    │ aws_iam_role.cluster │ AROA12345     │ name=eks-role   │
│ 007    │ aws_nat_gateway.a    │ nat-abc123    │ eip=52.1.2.3    │
├────────┴──────────────────────┴───────────────┴─────────────────┤
│ Total Resources: 7          Last Updated: 2026-03-19 14:32 UTC  │
└─────────────────────────────────────────────────────────────────┘
```

**Why "bank ledger" works:**
- If someone manually changes a resource (drift), it is like an unauthorized
  withdrawal. The ledger no longer matches reality.
- `terraform plan` is like an audit -- it compares the ledger to the real
  bank balance.
- `terraform refresh` updates the ledger to match reality without making changes.
- Corrupting the state file is like losing the bank's records. You still have
  money, but nobody knows how much or where.

### State as an "Inventory List"

```
  ┌─────────────────────────────────────────────────────┐
  │              INFRASTRUCTURE INVENTORY                 │
  │                                                       │
  │  Item: VPC                                            │
  │    Serial Number: vpc-0a1b2c3d                        │
  │    Location: us-east-1                                │
  │    Specs: 10.0.0.0/16, DNS enabled                   │
  │    Purchased: 2026-03-01                              │
  │    Last Verified: 2026-03-19                          │
  │                                                       │
  │  Item: EKS Cluster                                    │
  │    Serial Number: my-cluster                          │
  │    Location: us-east-1                                │
  │    Specs: v1.28, private endpoint, OIDC enabled      │
  │    Depends On: vpc-0a1b2c3d, subnet-1a2b3c           │
  │    Last Verified: 2026-03-19                          │
  │                                                       │
  │  If you lose this inventory, you still HAVE the       │
  │  items, but Terraform cannot manage them anymore.     │
  │  You would need to import each one back manually.     │
  └─────────────────────────────────────────────────────┘
```

### Local vs Remote State

```
  LOCAL STATE                              REMOTE STATE (S3 + DynamoDB)
  ─────────────────────                    ──────────────────────────────

  ┌──────────────┐                         ┌────────────────────────────┐
  │ Your Laptop  │                         │       AWS Cloud            │
  │              │                         │                            │
  │  ┌────────┐  │                         │  ┌──────────────────────┐  │
  │  │ Drawer │  │                         │  │   S3 Bucket          │  │
  │  │        │  │                         │  │   (Encrypted Vault)  │  │
  │  │ state  │  │                         │  │                      │  │
  │  │ file   │  │                         │  │   terraform.tfstate  │  │
  │  └────────┘  │                         │  │   (versioned)        │  │
  │              │                         │  └──────────────────────┘  │
  │  - Only you  │                         │                            │
  │    can see it│                         │  ┌──────────────────────┐  │
  │  - No backup │                         │  │   DynamoDB Table     │  │
  │  - No lock   │                         │  │   (Lock Manager)     │  │
  │  - Lost if   │                         │  │                      │  │
  │    laptop    │                         │  │   Prevents two       │  │
  │    dies      │                         │  │   people from        │  │
  └──────────────┘                         │  │   editing at once    │  │
                                           │  └──────────────────────┘  │
  Analogy:                                 │                            │
  Building plans kept in                   │  - Team access             │
  your desk drawer at home.                │  - Encrypted at rest       │
  Anyone who breaks in can                 │  - Versioned (undo!)       │
  see them. If your house                  │  - Locked during edits     │
  floods, they are gone.                   └────────────────────────────┘

                                           Analogy:
                                           Building plans in a bank vault.
                                           Only authorized people can access.
                                           The bank keeps copies. Only one
                                           person can check them out at a time.
```

### State Locking - Only One Editor at a Time

```
  Developer A                     DynamoDB                    Developer B
  ───────────                     ────────                    ───────────

  terraform apply
       |
       |  "I need the lock"
       |─────────────────────>  ┌──────────┐
       |                        │ LOCK     │
       |  "Lock granted"        │ Owner: A │
       |<─────────────────────  │ ID: abc  │
       |                        └──────────┘
       |                                          terraform apply
       |  (making changes...)                          |
       |                                               | "I need the lock"
       |                                               |──────────────>
       |                                               |
       |                                               | "DENIED - locked
       |                                               |  by Developer A"
       |                                               |<──────────────
       |                                               |
       |                                               X (Error: state locked)
       |  "I'm done, release"
       |─────────────────────>  ┌──────────┐
       |                        │ UNLOCKED │
       |                        └──────────┘
       |
      DONE

  This prevents two people from writing conflicting changes at the same time.
  Without locking, Developer A might create a subnet while Developer B deletes
  the VPC it depends on -- causing a corrupted, inconsistent state.
```

---

## 5. VPC Architecture - The Complete Picture

### Multi-AZ VPC Diagram

```
                              INTERNET
                                 |
                                 v
                        ┌────────────────┐
                        │ Internet       │
                        │ Gateway (IGW)  │
                        └───────┬────────┘
                                |
  ┌─────────────────────────────┼─────────────────────────────────────┐
  │                          VPC (10.0.0.0/16)                        │
  │                             |                                      │
  │  ┌──────────────────────────┼──────────────────────────────────┐  │
  │  │              Public Route Table: 0.0.0.0/0 -> IGW           │  │
  │  └──────────────────────────┼──────────────────────────────────┘  │
  │                             |                                      │
  │   us-east-1a               us-east-1b             us-east-1c      │
  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐            │
  │  │PUBLIC SUBNET │  │PUBLIC SUBNET │  │PUBLIC SUBNET │            │
  │  │10.0.1.0/24   │  │10.0.2.0/24   │  │10.0.3.0/24   │            │
  │  │              │  │              │  │              │            │
  │  │ [ALB]        │  │ [ALB]        │  │ [ALB]        │            │
  │  │ [NAT GW] ─────┐│ [NAT GW] ─────┐│              │            │
  │  └──────────────┘ ││└──────────────┘ ││└──────────────┘            │
  │                   ││                 ││                            │
  │  ┌────────────────┘│ ┌───────────────┘│                            │
  │  │  Private Route   │  Private Route   │                            │
  │  │  0.0.0.0->NAT-a │  0.0.0.0->NAT-b │                            │
  │  v                  v                  v                            │
  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐            │
  │  │PRIVATE SUBNET│  │PRIVATE SUBNET│  │PRIVATE SUBNET│            │
  │  │10.0.10.0/24  │  │10.0.11.0/24  │  │10.0.12.0/24  │            │
  │  │              │  │              │  │              │            │
  │  │ [EKS Node]   │  │ [EKS Node]   │  │ [EKS Node]   │            │
  │  │ [Pods]       │  │ [Pods]       │  │ [Pods]       │            │
  │  └──────────────┘  └──────────────┘  └──────────────┘            │
  │                                                                    │
  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐            │
  │  │DATABASE      │  │DATABASE      │  │DATABASE      │            │
  │  │SUBNET        │  │SUBNET        │  │SUBNET        │            │
  │  │10.0.20.0/24  │  │10.0.21.0/24  │  │10.0.22.0/24  │            │
  │  │              │  │              │  │              │            │
  │  │ [RDS Primary]│  │ [RDS Standby]│  │ [ElastiCache]│            │
  │  └──────────────┘  └──────────────┘  └──────────────┘            │
  │                                                                    │
  │  ┌─────────────────────────────────────────────────────────────┐  │
  │  │                    VPC Endpoints                             │  │
  │  │  ┌───────────┐ ┌──────────┐ ┌───────┐ ┌─────────┐          │  │
  │  │  │ S3 (GW)   │ │ECR (IF)  │ │STS    │ │CW Logs  │          │  │
  │  │  └───────────┘ └──────────┘ └───────┘ └─────────┘          │  │
  │  │  Traffic stays within AWS network -- no NAT charges         │  │
  │  └─────────────────────────────────────────────────────────────┘  │
  └────────────────────────────────────────────────────────────────────┘
```

### The "City Planning" Analogy

```
  VPC = The entire city limits (your private territory)

  Public Subnets = Main streets with public access
    - Anyone from the internet can reach services here
    - Like storefronts on a main road
    - Contains: Load balancers, NAT Gateways, bastion hosts

  Private Subnets = Residential neighborhoods behind gates
    - No direct access from the internet
    - Residents (pods) can go OUT to the internet via NAT Gateway
      (like a gated community with one exit to the main road)
    - Contains: Application servers, EKS worker nodes

  Database Subnets = Underground vaults
    - No internet access at all (inbound OR outbound)
    - Only accessible from private subnets
    - Like a bank vault that you can only reach from inside the bank
    - Contains: RDS, ElastiCache, other data stores

  Internet Gateway = The city entrance (highway on-ramp)
  NAT Gateway     = A one-way exit gate (residents can leave, visitors cannot enter)
  Route Tables    = Road signs telling traffic where to go
  VPC Endpoints   = Private tunnels directly to AWS services (no toll roads)
  Security Groups = Locks on individual building doors
  NACLs           = Neighborhood-level security checkpoints
```

### Traffic Flow - Ingress and Egress Paths

```
  INBOUND (User reaches your app):

  User ──> Internet ──> IGW ──> Public Subnet ──> ALB ──> Private Subnet ──> Pod
                                                    |
                                            SG allows :443
                                            from 0.0.0.0/0

  OUTBOUND (Pod pulls a Docker image):

  Pod ──> Private Subnet ──> NAT Gateway ──> IGW ──> Internet ──> docker.io
                                |
                         Pod has private IP only.
                         NAT translates to public IP.

  INTERNAL (Pod queries database):

  Pod ──> Private Subnet ──> Database Subnet ──> RDS
                                   |
                            SG allows :5432
                            from private subnet CIDR only.

  VPC ENDPOINT (Pod accesses S3 -- no internet needed):

  Pod ──> Private Subnet ──> VPC Endpoint ──> S3
                                   |
                          Traffic never leaves AWS network.
                          No NAT charges. Lower latency.
```

---

## 6. EKS Architecture - Visual Deep Dive

### Control Plane vs Data Plane

```
  ┌─────────────────────────────────────────────────────────────────┐
  │                    AWS MANAGED (Control Plane)                    │
  │                    You pay $0.10/hour for this                    │
  │                                                                   │
  │  ┌─────────────────────────────────────────────────────────┐     │
  │  │                  EKS Control Plane                       │     │
  │  │                                                          │     │
  │  │  ┌────────────┐  ┌─────────┐  ┌───────────────────┐    │     │
  │  │  │ API Server │  │  etcd   │  │ Controller Manager │    │     │
  │  │  │            │  │ (state) │  │ + Scheduler        │    │     │
  │  │  └────────────┘  └─────────┘  └───────────────────┘    │     │
  │  │                                                          │     │
  │  │  - Fully managed by AWS (patched, scaled, HA)           │     │
  │  │  - Runs across multiple AZs automatically               │     │
  │  │  - You NEVER SSH into these machines                    │     │
  │  └─────────────────────────────────────────────────────────┘     │
  │                            |                                      │
  │                     kubelet communication                         │
  │                            |                                      │
  ├────────────────────────────┼──────────────────────────────────────┤
  │                            |                                      │
  │                 YOU MANAGE (Data Plane)                            │
  │                 You pay for EC2 instances                          │
  │                                                                   │
  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐           │
  │  │   Node 1     │  │   Node 2     │  │   Node 3     │           │
  │  │ (t3.xlarge)  │  │ (t3.xlarge)  │  │ (m5.2xlarge) │           │
  │  │              │  │              │  │              │           │
  │  │ ┌──────────┐ │  │ ┌──────────┐ │  │ ┌──────────┐ │           │
  │  │ │ kubelet  │ │  │ │ kubelet  │ │  │ │ kubelet  │ │           │
  │  │ └──────────┘ │  │ └──────────┘ │  │ └──────────┘ │           │
  │  │ ┌──┐ ┌──┐   │  │ ┌──┐ ┌──┐   │  │ ┌──┐ ┌──┐   │           │
  │  │ │P1│ │P2│   │  │ │P3│ │P4│   │  │ │P5│ │P6│   │           │
  │  │ └──┘ └──┘   │  │ └──┘ └──┘   │  │ └──┘ └──┘   │           │
  │  │   (Pods)     │  │   (Pods)     │  │   (Pods)     │           │
  │  └──────────────┘  └──────────────┘  └──────────────┘           │
  └─────────────────────────────────────────────────────────────────┘
```

### The "Company Building" Analogy

```
  EKS Cluster = An entire company office building

  Control Plane (Management Floor):
    - API Server    = Reception desk (all requests go through here)
    - etcd          = The filing cabinet (records everything)
    - Scheduler     = HR department (assigns workers to desks)
    - Controllers   = Managers (ensure the right number of workers are present)

  Data Plane (Worker Floors):
    - Nodes         = Office floors (physical space)
    - Pods          = Individual employees at their desks
    - kubelet       = Floor manager (reports to management, starts/stops workers)
    - Containers    = The actual tasks each employee is performing

  You (the CTO) talk to Reception (API Server).
  You never go to the management floor yourself -- AWS handles that.
  You decide how many worker floors (nodes) you need and what kind of
  employees (pods) work on each floor.
```

### OIDC and IRSA Flow Diagram

IRSA (IAM Roles for Service Accounts) lets pods assume IAM roles securely.

```
  Step 1: Setup (done once by Terraform)
  ────────────────────────────────────────

  EKS Cluster ──creates──> OIDC Provider (identity issuer)
       |
       v
  IAM Role ──trust policy──> "I trust tokens from this OIDC Provider
                               for service account 'X' in namespace 'Y'"

  Step 2: Runtime (every time a pod starts)
  ──────────────────────────────────────────

  ┌───────────┐    1. Pod starts with          ┌─────────────────┐
  │   Pod     │       ServiceAccount annotation │  Kubernetes     │
  │           │ <──────────────────────────────  │  API Server     │
  │ SA: my-sa │    2. K8s injects a JWT token   └─────────────────┘
  │           │       into the pod
  └─────┬─────┘
        |
        |  3. Pod calls AWS API with the JWT token
        v
  ┌─────────────────┐
  │   AWS STS       │    4. STS validates the JWT:
  │                 │       - Is the OIDC provider trusted?
  │  AssumeRole     │       - Is the service account correct?
  │  WithWebIdentity│       - Is the namespace correct?
  └────────┬────────┘
           |
           |  5. STS returns temporary AWS credentials
           v
  ┌─────────────────┐
  │  AWS Service    │    6. Pod uses credentials to access S3,
  │  (e.g. S3)     │       DynamoDB, etc. -- with ONLY the
  │                 │       permissions defined in the IAM role.
  └─────────────────┘
```

### Pod to User - The Full Request Path

```
  ┌──────┐    ┌─────────┐    ┌──────────┐    ┌───────────────┐
  │ User │───>│ Route53 │───>│   ALB    │───>│   Ingress     │
  │      │    │  (DNS)  │    │ (Layer 7)│    │   Controller  │
  └──────┘    └─────────┘    └──────────┘    └───────┬───────┘
                                                      |
                                                      v
                                             ┌───────────────┐
                                             │  K8s Service  │
                                             │  (ClusterIP)  │
                                             └───────┬───────┘
                                                      |
                                               ┌──────┼──────┐
                                               v      v      v
                                            ┌─────┐┌─────┐┌─────┐
                                            │Pod 1││Pod 2││Pod 3│
                                            └─────┘└─────┘└─────┘

  What each component does:
    Route53:            Translates app.example.com -> ALB IP address
    ALB:                Terminates TLS, routes HTTP requests by path/host
    Ingress Controller: Watches K8s Ingress resources, configures ALB rules
    Service:            Internal load balancer across pods (virtual IP)
    Pods:               Your actual application containers
```

### Node Group Scaling Visualization

```
  Desired: 3     Min: 2     Max: 10

  Low Load:
  ┌──────┐ ┌──────┐
  │Node 1│ │Node 2│  (2 nodes = minimum)
  │ P P  │ │ P    │
  └──────┘ └──────┘

  Normal Load:
  ┌──────┐ ┌──────┐ ┌──────┐
  │Node 1│ │Node 2│ │Node 3│  (3 nodes = desired)
  │ P P  │ │ P P  │ │ P P  │
  └──────┘ └──────┘ └──────┘

  High Load:
  ┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐
  │Node 1│ │Node 2│ │Node 3│ │Node 4│ │Node 5│ │Node 6│
  │PPPPPP│ │PPPPPP│ │PPPPPP│ │PPPPPP│ │PPPPPP│ │ P P  │
  └──────┘ └──────┘ └──────┘ └──────┘ └──────┘ └──────┘
  (Autoscaler added nodes because pods could not be scheduled)

  Peak Load:
  ┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐ ... ┌───────┐
  │Node 1│ │Node 2│ │Node 3│ │Node 4│ │Node 5│     │Node 10│
  │PPPPPP│ │PPPPPP│ │PPPPPP│ │PPPPPP│ │PPPPPP│     │PPPPPP │
  └──────┘ └──────┘ └──────┘ └──────┘ └──────┘     └───────┘
  (10 nodes = maximum -- cannot scale further, pods will go Pending)
```

---

## 7. Networking Flow - From User to Pod

### The Complete Journey

```
┌──────────────────────────────────────────────────────────────────────┐
│                     THE COMPLETE REQUEST PATH                        │
│                                                                      │
│  ┌──────────┐                                                        │
│  │  User's  │  1. Types "app.example.com" in browser                │
│  │  Browser │                                                        │
│  └────┬─────┘                                                        │
│       |                                                              │
│       | DNS query                                                    │
│       v                                                              │
│  ┌──────────┐  2. Returns ALB IP: 52.1.2.3                         │
│  │ Route 53 │     (or CloudFront distribution if CDN is used)       │
│  └────┬─────┘                                                        │
│       |                                                              │
│       | HTTPS request to 52.1.2.3:443                               │
│       v                                                              │
│  ┌──────────┐  3. Terminates TLS (ACM certificate)                  │
│  │   ALB    │     Checks path rules:                                │
│  │          │       /api/*  -> target group A                       │
│  │          │       /*      -> target group B                       │
│  └────┬─────┘                                                        │
│       |                                                              │
│       | HTTP to node:port (target group)                            │
│       v                                                              │
│  ┌──────────────┐  4. AWS Load Balancer Controller registered       │
│  │   Ingress    │     nodes as targets. Traffic arrives at          │
│  │   Controller │     NodePort on the target node.                  │
│  └──────┬───────┘                                                    │
│         |                                                            │
│         | iptables/IPVS rules (kube-proxy)                          │
│         v                                                            │
│  ┌──────────────┐  5. ClusterIP service selects a healthy pod      │
│  │  Kubernetes  │     based on label selectors. Distributes         │
│  │  Service     │     traffic across pods (round-robin by default). │
│  └──────┬───────┘                                                    │
│         |                                                            │
│         | Direct pod-to-pod networking (VPC CNI)                    │
│         v                                                            │
│  ┌──────────────┐  6. Pod receives the request, processes it,      │
│  │     Pod      │     returns response. The response travels        │
│  │  (Container) │     back the same path in reverse.                │
│  └──────────────┘                                                    │
└──────────────────────────────────────────────────────────────────────┘
```

### Where Things Can Break at Each Layer

```
  Layer            What Can Break                  How to Debug
  ──────────────── ──────────────────────────────── ──────────────────────────────
  DNS (Route53)    Wrong record, propagation delay  dig app.example.com
                                                    nslookup app.example.com

  ALB              Bad listener rules, no healthy   AWS Console -> Target Groups
                   targets, security group blocks    -> Health check status

  Ingress          Wrong annotation, class mismatch kubectl get ingress -A
                   missing ingress controller        kubectl describe ingress X

  Service          Wrong selector, no endpoints      kubectl get endpoints svc-name
                                                     kubectl describe svc svc-name

  Pod              CrashLoopBackOff, OOMKilled,      kubectl logs pod-name
                   wrong port, readiness probe fail  kubectl describe pod pod-name

  Network          Security group too restrictive,   VPC Flow Logs
                   NACL blocking, no route to NAT    kubectl exec -it pod -- curl
```

---

## 8. IAM and IRSA - Visual Explanation

### IAM Role Assumption Flow

```
  ┌──────────────────┐         ┌──────────────────┐
  │   PRINCIPAL      │         │   IAM ROLE       │
  │                  │         │                  │
  │ "I am Pod X     │ ──────> │ Trust Policy:    │
  │  and I want to  │ assume  │ "I allow Pod X   │
  │  assume this    │ role    │  to become me"   │
  │  role"          │         │                  │
  └──────────────────┘         │ Permissions:     │
                               │ "I can read S3   │
                               │  bucket Y"       │
                               └────────┬─────────┘
                                        |
                                        | temporary credentials
                                        v
                               ┌──────────────────┐
                               │   AWS SERVICE    │
                               │   (S3 Bucket Y)  │
                               │                  │
                               │ "Credentials     │
                               │  valid. Access   │
                               │  granted."       │
                               └──────────────────┘
```

### The IRSA Trust Chain

```
  ┌─────────────────┐
  │ Terraform Code  │  Creates all of these:
  └────────┬────────┘
           |
           |  1. Creates OIDC Provider
           |     (registers EKS as an identity issuer with IAM)
           |
           |  2. Creates IAM Role with trust policy:
           |     {
           |       "Effect": "Allow",
           |       "Principal": { "Federated": "arn:aws:iam::oidc-provider/..." },
           |       "Action": "sts:AssumeRoleWithWebIdentity",
           |       "Condition": {
           |         "StringEquals": {
           |           "sub": "system:serviceaccount:NAMESPACE:SA_NAME"
           |         }
           |       }
           |     }
           |
           |  3. Creates IAM Policy (what the role can do)
           |
           |  4. Creates K8s ServiceAccount with annotation:
           |     eks.amazonaws.com/role-arn: arn:aws:iam::role/my-role
           |
           v

  RUNTIME CHAIN:

  Pod (with ServiceAccount)
    --> K8s injects OIDC token (JWT) as a projected volume
      --> Pod SDK calls sts:AssumeRoleWithWebIdentity with the JWT
        --> STS validates: OIDC issuer + namespace + SA name
          --> STS returns temp credentials (15min - 12hr)
            --> Pod calls AWS API with temp credentials
              --> IAM checks permissions on the role
                --> Access granted (or denied)
```

### The "Hotel Key Card" Analogy

```
  ┌────────────────────────────────────────────────────────────────┐
  │                    THE HOTEL KEY CARD ANALOGY                   │
  │                                                                 │
  │  IAM User/Role    = Guest registration (who you are)           │
  │  IAM Policy       = Key card programming (which rooms/floors)  │
  │  STS Credentials  = The actual key card (temporary, expires)   │
  │  OIDC Provider    = The hotel chain's central ID system        │
  │  Service Account  = Your reservation confirmation number       │
  │                                                                 │
  │  The Flow:                                                      │
  │                                                                 │
  │  1. You (Pod) arrive at the hotel (AWS)                        │
  │  2. You show your reservation (ServiceAccount + OIDC token)    │
  │  3. Front desk (STS) checks with HQ (OIDC Provider)           │
  │  4. HQ confirms: "Yes, this guest has a valid reservation"    │
  │  5. Front desk gives you a key card (temporary credentials)    │
  │  6. Key card opens Room 301 (S3) and the gym (DynamoDB)       │
  │  7. Key card does NOT open Room 502 (production database)     │
  │  8. Key card expires at checkout time (credential expiry)      │
  │                                                                 │
  │  No master keys. No permanent access. No shared keys.          │
  │  Every guest gets their own card with specific permissions.    │
  └────────────────────────────────────────────────────────────────┘
```

### Step-by-Step: Pod Needs S3 Access

```
  WHAT YOU WRITE (Terraform):

  1. IAM Role:          "s3-reader-role" with S3 read policy
  2. Trust Policy:      Allows OIDC from EKS, for SA "s3-reader" in namespace "app"
  3. ServiceAccount:    "s3-reader" annotated with the role ARN
  4. Pod Spec:          serviceAccountName: s3-reader

  WHAT HAPPENS AT RUNTIME:

  ┌─────────────────────────────────────────────────────────────┐
  │ Pod starts -> K8s mounts JWT token at:                      │
  │   /var/run/secrets/eks.amazonaws.com/serviceaccount/token   │
  │                                                              │
  │ AWS SDK in your app automatically:                           │
  │   1. Reads the token file                                    │
  │   2. Calls sts:AssumeRoleWithWebIdentity                    │
  │   3. Gets back: AccessKeyId, SecretAccessKey, SessionToken  │
  │   4. Uses these to call s3:GetObject                        │
  │   5. Refreshes credentials before they expire               │
  │                                                              │
  │ Your app code just does:                                     │
  │   s3_client = boto3.client('s3')    # credentials are       │
  │   s3_client.get_object(...)         # handled automatically │
  └─────────────────────────────────────────────────────────────┘
```

---

## 9. CI/CD Pipeline Visualization

### Pipeline Stages

```
  ┌─────────┐   ┌──────────┐   ┌──────────┐   ┌──────────┐   ┌──────────┐
  │  CODE   │──>│  BUILD   │──>│   TEST   │──>│  PLAN    │──>│  APPLY   │
  └─────────┘   └──────────┘   └──────────┘   └──────────┘   └──────────┘
       |             |              |              |              |
  git push      terraform      terraform      terraform      terraform
  triggers      fmt -check     validate       plan -out=     apply
  pipeline      tflint         tfsec/checkov  tfplan         tfplan
                terraform      unit tests
                init

  Failure at any stage STOPS the pipeline. No partial applies.

  ┌─────────────────────────────────────────────────────────────────┐
  │                  DETAIL: PLAN STAGE                              │
  │                                                                  │
  │  terraform plan -out=tfplan                                     │
  │       |                                                          │
  │       v                                                          │
  │  ┌──────────────────────────────────┐                           │
  │  │ Plan output posted as a comment  │                           │
  │  │ on the Pull Request:             │                           │
  │  │                                  │                           │
  │  │  + aws_subnet.new     (create)  │                           │
  │  │  ~ aws_instance.web   (modify)  │                           │
  │  │  - aws_s3_bucket.old  (destroy) │                           │
  │  └──────────────────────────────────┘                           │
  │       |                                                          │
  │       v                                                          │
  │  ┌──────────────────────────────────┐                           │
  │  │  MANUAL APPROVAL GATE            │                           │
  │  │  Senior engineer reviews plan    │                           │
  │  │  and clicks "Approve"            │  <--- Only THEN does     │
  │  └──────────────────────────────────┘       apply run           │
  └─────────────────────────────────────────────────────────────────┘
```

### Branch Strategy Diagram

```
  main (production)
  ──●──────────────────●───────────────────────●──────────────
    |                  ^                       ^
    |                  | merge (after approve) | merge
    |                  |                       |
    |   develop        |                       |
    └──●───────●───────●──────●────────────────●──────────────
       |       ^              ^
       |       | merge        | merge
       |       |              |
       |  feature/add-rds     |
       └──●──●──●─────────   |
                              |
          feature/update-vpc  |
          ●──●──●──●──────────┘

  Rules:
    - feature/* branches: Created from develop, merged back to develop
    - develop branch:     Integration branch, auto-deploys to staging
    - main branch:        Production only, requires approval to merge
    - No direct commits to main or develop
```

### Environment Promotion Flow

```
  ┌──────────┐         ┌──────────┐         ┌──────────────┐
  │   DEV    │ ──────> │ STAGING  │ ──────> │  PRODUCTION  │
  └──────────┘  auto   └──────────┘  manual └──────────────┘
                                     approval
  Terraform      Terraform            Terraform
  workspace:     workspace:           workspace:
  dev            staging              prod

  State file:    State file:          State file:
  s3://tf/dev/   s3://tf/staging/     s3://tf/prod/
  tfstate        tfstate              tfstate

  Variables:     Variables:           Variables:
  t3.medium      t3.large             m5.2xlarge
  1 NAT GW       2 NAT GWs           3 NAT GWs
  2 nodes        3 nodes              6-20 nodes
  no multi-AZ    multi-AZ             multi-AZ + DR
```

### Approval Gates Visualization

```
  PR Created ──> CI Runs ──> Plan Generated ──> Review Required
                                                      |
                                          ┌───────────┼───────────┐
                                          v           v           v
                                    ┌──────────┐┌──────────┐┌──────────┐
                                    │ Code     ││ Security ││ Platform │
                                    │ Review   ││ Review   ││ Review   │
                                    │ (peer)   ││ (tfsec)  ││ (senior) │
                                    └────┬─────┘└────┬─────┘└────┬─────┘
                                         |           |           |
                                         v           v           v
                                    ALL APPROVED? ──────────> terraform apply
                                         |
                                    ANY REJECTED? ──────────> Pipeline stops
                                                              Fix and re-push
```

---

## 10. Scaling Visualizations

### HPA Decision Loop

The Horizontal Pod Autoscaler runs a continuous control loop:

```
  ┌──────────────────────────────────────────────────────┐
  │              HPA CONTROL LOOP (every 15s)             │
  │                                                       │
  │    ┌──────────────────────────┐                       │
  │    │ 1. Read current metrics  │                       │
  │    │    (CPU, memory, custom) │                       │
  │    └────────────┬─────────────┘                       │
  │                 |                                      │
  │                 v                                      │
  │    ┌──────────────────────────┐                       │
  │    │ 2. Calculate desired     │                       │
  │    │    replicas:             │                       │
  │    │                          │                       │
  │    │    desired = ceil(       │                       │
  │    │      current_replicas *  │                       │
  │    │      current_metric /    │                       │
  │    │      target_metric       │                       │
  │    │    )                     │                       │
  │    └────────────┬─────────────┘                       │
  │                 |                                      │
  │           ┌─────┼─────┐                               │
  │           v     v     v                               │
  │         SAME  SCALE  SCALE                            │
  │               UP     DOWN                             │
  │               |      |                                │
  │               v      v                                │
  │    ┌─────────────┐ ┌───────────────┐                  │
  │    │ Add pods    │ │ Remove pods   │                  │
  │    │ immediately │ │ (wait 5 min   │                  │
  │    │             │ │  stabilization│                  │
  │    │             │ │  window)      │                  │
  │    └─────────────┘ └───────────────┘                  │
  │                                                       │
  │    Example:                                           │
  │    Target CPU: 70% | Current CPU: 140% | Pods: 2     │
  │    Desired = ceil(2 * 140/70) = ceil(4.0) = 4 pods   │
  │    Action: Scale from 2 to 4 pods                     │
  └──────────────────────────────────────────────────────┘
```

### Cluster Autoscaler vs Karpenter

```
  ┌──────────────────────────────────┐  ┌──────────────────────────────────┐
  │      CLUSTER AUTOSCALER          │  │         KARPENTER                │
  ├──────────────────────────────────┤  ├──────────────────────────────────┤
  │                                  │  │                                  │
  │  Pre-defined Node Groups:       │  │  No Node Groups needed:         │
  │                                  │  │                                  │
  │  ┌────────────────────┐          │  │  Pending Pod                    │
  │  │ Node Group A       │          │  │    |                            │
  │  │ t3.large, 2-10     │          │  │    v                            │
  │  └────────┬───────────┘          │  │  Karpenter evaluates:           │
  │           |                      │  │    - Pod requirements            │
  │  ┌────────────────────┐          │  │    - Available instance types    │
  │  │ Node Group B       │          │  │    - Spot vs On-Demand prices   │
  │  │ m5.xlarge, 1-5     │          │  │    - AZ distribution            │
  │  └────────┬───────────┘          │  │    |                            │
  │           |                      │  │    v                            │
  │  Pending Pod?                    │  │  Launches BEST FIT instance    │
  │    |                             │  │  (could be any type)            │
  │    v                             │  │                                  │
  │  Try each node group:           │  │  ┌─────┐ ┌──────┐ ┌───────┐   │
  │  "Does this fit?"               │  │  │c5.lg│ │m5.xl │ │r6i.2xl│   │
  │    |                             │  │  └─────┘ └──────┘ └───────┘   │
  │    v                             │  │  Right-sized for the workload  │
  │  Scale THAT group +1            │  │                                  │
  │                                  │  │  Also consolidates:            │
  │  Limitation:                     │  │  Under-utilized nodes are      │
  │  Might launch a too-big or      │  │  replaced with better-fitting  │
  │  too-small instance if the      │  │  ones automatically.           │
  │  node group is not optimal.     │  │                                  │
  └──────────────────────────────────┘  └──────────────────────────────────┘

  Summary:
    Cluster Autoscaler = "Choose from a menu" (pre-defined node groups)
    Karpenter          = "Chef's choice" (picks the best option dynamically)
```

### Spot Instance Lifecycle

```
  ┌────────────┐     ┌──────────────┐     ┌──────────────┐
  │ Request    │────>│ AWS Launches │────>│ Running      │
  │ Spot       │     │ Instance     │     │ (up to 90%   │
  │ Instance   │     │ ($0.012/hr   │     │  cheaper!)   │
  └────────────┘     │  vs $0.04)   │     └──────┬───────┘
                     └──────────────┘            |
                                                  | AWS needs capacity back
                                                  v
                                         ┌──────────────────┐
                                         │ 2-MINUTE WARNING │
                                         │                  │
                                         │ Instance metadata│
                                         │ endpoint signals │
                                         │ termination.     │
                                         └────────┬─────────┘
                                                  |
                                    ┌─────────────┼─────────────┐
                                    v             v             v
                             ┌───────────┐ ┌───────────┐ ┌───────────┐
                             │ Drain node│ │ Cordon    │ │ Karpenter │
                             │ (evict   │ │ node      │ │ launches  │
                             │  pods)    │ │ (no new   │ │ replacment│
                             └───────────┘ │  pods)    │ │ node      │
                                           └───────────┘ └───────────┘
                                                  |
                                                  v
                                         ┌──────────────────┐
                                         │ Instance          │
                                         │ Terminated        │
                                         │ Pods rescheduled  │
                                         │ on other nodes    │
                                         └──────────────────┘

  Best practice: Run stateless workloads on Spot. Use Pod Disruption Budgets
  to ensure not all replicas are evicted simultaneously.
```

### The "Highway Traffic" Analogy for Autoscaling

```
  Think of your cluster as a highway system:

  Pods    = Cars on the highway
  Nodes   = Highway lanes
  HPA     = Traffic control (tells more cars to use the road, or fewer)
  CA      = Road construction crew (adds more lanes when traffic is heavy)

  ┌──────────────────────────────────────────────────────────────┐
  │                                                              │
  │  LOW TRAFFIC (2 AM):                                        │
  │  ═══🚗═══════════🚗══════════════                           │
  │  ═══════🚗═══════════════════════    2 lanes open           │
  │                                                              │
  │  RUSH HOUR (9 AM):                                          │
  │  ═🚗🚗🚗🚗🚗🚗🚗🚗🚗🚗🚗🚗═══                           │
  │  ═🚗🚗🚗🚗🚗🚗🚗🚗🚗🚗🚗🚗═══                           │
  │  ═🚗🚗🚗🚗🚗🚗🚗🚗🚗🚗═══════    4 lanes (HPA added     │
  │  ═🚗🚗🚗🚗🚗🚗🚗═════════════    more cars; CA opened     │
  │                                     more lanes)              │
  │                                                              │
  │  AFTER RUSH HOUR (11 AM):                                   │
  │  ═══🚗🚗═══🚗══════🚗═════════                             │
  │  ═══🚗════🚗══════════════════    Scale down: fewer cars,   │
  │  ═══════════════════════════════    extra lanes close         │
  │  (closed lane)                     (nodes terminated)        │
  │                                                              │
  │  HPA = decides how many cars (pods)                         │
  │  Cluster Autoscaler = decides how many lanes (nodes)        │
  │  Both work TOGETHER: HPA creates demand, CA provides supply │
  └──────────────────────────────────────────────────────────────┘
```

---

## 11. Cost Flow Diagram

### Where Money Goes in an EKS Setup

```
  ┌──────────────────────────────────────────────────────────────────┐
  │              MONTHLY EKS COST BREAKDOWN (Typical Production)     │
  │                                                                   │
  │  ┌──────────────────────────────────────────────────────────┐    │
  │  │ EKS Control Plane                               $73/mo  │    │
  │  │ ($0.10/hr x 730 hrs)                                     │    │
  │  │ FIXED -- same whether you have 1 or 100 nodes           │    │
  │  └──────────────────────────────────────────────────────────┘    │
  │                                                                   │
  │  ┌──────────────────────────────────────────────────────────┐    │
  │  │ EC2 Worker Nodes                          ~$400-2000/mo  │    │
  │  │ (depends on instance types and count)                     │    │
  │  │                                                           │    │
  │  │   3x t3.xlarge On-Demand:   3 x $0.1664/hr = $364/mo   │    │
  │  │   3x t3.xlarge Spot:        3 x $0.0499/hr = $109/mo   │    │
  │  │                                                           │    │
  │  │ >>> BIGGEST COST LEVER -- use Spot, right-size <<<       │    │
  │  └──────────────────────────────────────────────────────────┘    │
  │                                                                   │
  │  ┌──────────────────────────────────────────────────────────┐    │
  │  │ NAT Gateways                               ~$90-300/mo  │    │
  │  │                                                           │    │
  │  │   Per gateway: $0.045/hr = $32/mo                        │    │
  │  │   Per GB processed: $0.045/GB                            │    │
  │  │                                                           │    │
  │  │   2 NAT GWs + 500GB traffic:                             │    │
  │  │   (2 x $32) + (500 x $0.045) = $86.50/mo               │    │
  │  │                                                           │    │
  │  │ >>> Use VPC Endpoints to reduce NAT traffic <<<          │    │
  │  └──────────────────────────────────────────────────────────┘    │
  │                                                                   │
  │  ┌──────────────────────────────────────────────────────────┐    │
  │  │ Data Transfer                                ~$50-500/mo │    │
  │  │                                                           │    │
  │  │   Cross-AZ:  $0.01/GB each direction                    │    │
  │  │   To Internet: $0.09/GB (first 10TB)                    │    │
  │  │   Within AZ:  FREE                                       │    │
  │  │                                                           │    │
  │  │ >>> Keep chatty services in the same AZ <<<              │    │
  │  └──────────────────────────────────────────────────────────┘    │
  │                                                                   │
  │  ┌──────────────────────────────────────────────────────────┐    │
  │  │ Storage (EBS, S3)                            ~$20-100/mo │    │
  │  │   EBS gp3: $0.08/GB/mo                                  │    │
  │  │   S3:      $0.023/GB/mo                                  │    │
  │  └──────────────────────────────────────────────────────────┘    │
  │                                                                   │
  │  ┌──────────────────────────────────────────────────────────┐    │
  │  │ Other: ALB ($16/mo + LCU), CloudWatch Logs, Route53     │    │
  │  │        VPC Endpoints ($7.30/mo each), ECR storage        │    │
  │  │                                          ~$30-100/mo     │    │
  │  └──────────────────────────────────────────────────────────┘    │
  │                                                                   │
  │  ────────────────────────────────────────────────────────────    │
  │  TOTAL (typical 3-node production):         ~$650-1200/mo       │
  │  TOTAL (with Spot + optimizations):         ~$350-600/mo        │
  │                                                                   │
  │  OPTIMIZATION CHECKLIST:                                         │
  │  [x] Use Spot instances for stateless workloads (save 60-70%)   │
  │  [x] Add VPC Endpoints for S3, ECR, STS (reduce NAT costs)     │
  │  [x] Right-size nodes (do not over-provision)                   │
  │  [x] Use gp3 instead of gp2 EBS volumes (20% cheaper)          │
  │  [x] Enable S3 lifecycle rules (archive old data)               │
  │  [x] Shut down dev/staging at night (Karpenter TTL)             │
  └──────────────────────────────────────────────────────────────────┘
```

---

## 12. Security Layers - The Onion Model

### Concentric Security Layers

```
  ┌─────────────────────────────────────────────────────────────────────┐
  │  AWS ACCOUNT (outermost layer)                                      │
  │  Protection: MFA, SCPs, CloudTrail, GuardDuty                      │
  │                                                                     │
  │  ┌───────────────────────────────────────────────────────────────┐  │
  │  │  VPC (network isolation)                                      │  │
  │  │  Protection: Private IP space, no default internet access     │  │
  │  │                                                               │  │
  │  │  ┌─────────────────────────────────────────────────────────┐  │  │
  │  │  │  SUBNET (network segmentation)                          │  │  │
  │  │  │  Protection: NACLs, route tables, public/private split  │  │  │
  │  │  │                                                         │  │  │
  │  │  │  ┌───────────────────────────────────────────────────┐  │  │  │
  │  │  │  │  SECURITY GROUP (instance firewall)               │  │  │  │
  │  │  │  │  Protection: Port/protocol/source filtering       │  │  │  │
  │  │  │  │                                                   │  │  │  │
  │  │  │  │  ┌─────────────────────────────────────────────┐  │  │  │  │
  │  │  │  │  │  NODE (EC2 instance)                        │  │  │  │  │
  │  │  │  │  │  Protection: IMDSv2, hardened AMI, no SSH   │  │  │  │  │
  │  │  │  │  │                                             │  │  │  │  │
  │  │  │  │  │  ┌───────────────────────────────────────┐  │  │  │  │  │
  │  │  │  │  │  │  POD (Kubernetes workload)            │  │  │  │  │  │
  │  │  │  │  │  │  Protection: NetworkPolicy, RBAC,     │  │  │  │  │  │
  │  │  │  │  │  │  PodSecurityStandards, IRSA           │  │  │  │  │  │
  │  │  │  │  │  │                                       │  │  │  │  │  │
  │  │  │  │  │  │  ┌─────────────────────────────────┐  │  │  │  │  │  │
  │  │  │  │  │  │  │  CONTAINER (innermost layer)    │  │  │  │  │  │  │
  │  │  │  │  │  │  │  Protection: Read-only FS,      │  │  │  │  │  │  │
  │  │  │  │  │  │  │  non-root user, seccomp,        │  │  │  │  │  │  │
  │  │  │  │  │  │  │  dropped capabilities,          │  │  │  │  │  │  │
  │  │  │  │  │  │  │  minimal base image             │  │  │  │  │  │  │
  │  │  │  │  │  │  └─────────────────────────────────┘  │  │  │  │  │  │
  │  │  │  │  │  └───────────────────────────────────────┘  │  │  │  │  │
  │  │  │  │  └─────────────────────────────────────────────┘  │  │  │  │
  │  │  │  └───────────────────────────────────────────────────┘  │  │  │
  │  │  └─────────────────────────────────────────────────────────┘  │  │
  │  └───────────────────────────────────────────────────────────────┘  │
  └─────────────────────────────────────────────────────────────────────┘
```

### What Each Layer Protects Against

```
  Layer            Protects Against                   If Breached
  ──────────────── ───────────────────────────────── ────────────────────────────
  AWS Account      Unauthorized account access        Attacker controls everything
  VPC              Cross-network attacks              Attacker is in your network
  Subnet + NACLs   Lateral movement between tiers     Attacker reaches databases
  Security Group   Unauthorized port access            Attacker connects to services
  Node             Node compromise, privilege escal.  Attacker runs code on host
  Pod              Pod-to-pod attacks, data theft      Attacker in one workload
  Container        Container escape, file tampering   Attacker runs arbitrary code

  Defense in depth: even if one layer fails, the next layer stops the attacker.
  No single layer is sufficient on its own.
```

---

## 13. The Complete EKS Production Stack

### Everything Together

```
┌──────────────────────────────────────────────────────────────────────────┐
│                           AWS ACCOUNT                                    │
│  CloudTrail | GuardDuty | AWS Config | Cost Explorer | IAM              │
│                                                                          │
│  ┌──────────────────────────────────────────────────────────────────┐   │
│  │                        VPC (10.0.0.0/16)                         │   │
│  │                                                                   │   │
│  │  ┌───────────────────── PUBLIC SUBNETS ──────────────────────┐   │   │
│  │  │  AZ-a: 10.0.1.0/24  |  AZ-b: 10.0.2.0/24  |  AZ-c      │   │   │
│  │  │                      |                       |             │   │   │
│  │  │  [IGW] ── route ──> all three subnets                     │   │   │
│  │  │  [ALB] targets registered by AWS LB Controller            │   │   │
│  │  │  [NAT-a] [NAT-b] outbound for private subnets            │   │   │
│  │  └───────────────────────────────────────────────────────────┘   │   │
│  │                               |                                   │   │
│  │  ┌──────────────────── PRIVATE SUBNETS ──────────────────────┐   │   │
│  │  │  AZ-a: 10.0.10.0/24  |  AZ-b: 10.0.11.0/24  |  AZ-c    │   │   │
│  │  │                       |                        |           │   │   │
│  │  │  ┌───────────────── EKS CLUSTER ──────────────────────┐   │   │   │
│  │  │  │                                                     │   │   │   │
│  │  │  │  Control Plane (AWS Managed):                      │   │   │   │
│  │  │  │    API Server | etcd | Controllers | Scheduler     │   │   │   │
│  │  │  │    OIDC Provider (for IRSA)                        │   │   │   │
│  │  │  │                                                     │   │   │   │
│  │  │  │  Node Group (Your EC2 instances):                  │   │   │   │
│  │  │  │  ┌─────────┐ ┌─────────┐ ┌─────────┐              │   │   │   │
│  │  │  │  │ Node 1  │ │ Node 2  │ │ Node 3  │              │   │   │   │
│  │  │  │  │         │ │         │ │         │              │   │   │   │
│  │  │  │  │ coredns │ │ lb-ctrl │ │ cl-auto │  Add-ons    │   │   │   │
│  │  │  │  │ app-pod │ │ app-pod │ │ app-pod │  Workloads  │   │   │   │
│  │  │  │  │ fluentd │ │ prom    │ │ grafana │  Monitoring │   │   │   │
│  │  │  │  └─────────┘ └─────────┘ └─────────┘              │   │   │   │
│  │  │  │                                                     │   │   │   │
│  │  │  │  IRSA Roles:                                       │   │   │   │
│  │  │  │    lb-controller-role (manages ALB)                │   │   │   │
│  │  │  │    cluster-autoscaler-role (manages ASG)           │   │   │   │
│  │  │  │    external-dns-role (manages Route53)             │   │   │   │
│  │  │  │    app-role (accesses S3, DynamoDB)                │   │   │   │
│  │  │  └─────────────────────────────────────────────────────┘   │   │   │
│  │  └───────────────────────────────────────────────────────────┘   │   │
│  │                                                                   │   │
│  │  ┌──────────────────── DATABASE SUBNETS ─────────────────────┐   │   │
│  │  │  AZ-a: 10.0.20.0/24  |  AZ-b: 10.0.21.0/24              │   │   │
│  │  │  [RDS Primary]        |  [RDS Standby]                    │   │   │
│  │  └───────────────────────────────────────────────────────────┘   │   │
│  │                                                                   │   │
│  │  VPC Endpoints: S3 | ECR-api | ECR-dkr | STS | CW-logs         │   │
│  └───────────────────────────────────────────────────────────────────┘   │
│                                                                          │
│  External Services:                                                      │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌───────────┐    │
│  │ Route53  │ │ ACM      │ │ CW Logs  │ │ ECR      │ │ S3        │    │
│  │ (DNS)    │ │ (TLS)    │ │ (Logs)   │ │ (Images) │ │ (State+   │    │
│  │          │ │          │ │          │ │          │ │  Data)    │    │
│  └──────────┘ └──────────┘ └──────────┘ └──────────┘ └───────────┘    │
└──────────────────────────────────────────────────────────────────────────┘
```

### The "City Infrastructure" Analogy

```
  Mapping the entire stack to a city:

  AWS Account          = The country (laws, regulations, audits)
  VPC                  = A city with clear borders
  Internet Gateway     = The main highway entrance to the city
  Public Subnets       = Commercial district (shops, restaurants -- public facing)
  NAT Gateways         = One-way exit tunnels (residents can leave; outsiders cannot enter)
  Private Subnets      = Residential district (behind gates, private)
  Database Subnets     = Underground vaults (maximum security, no outside access)
  EKS Control Plane    = City Hall (manages everything, you do not go there directly)
  Worker Nodes         = Office buildings (provide space for businesses)
  Pods                 = Employees in those buildings (do the actual work)
  ALB                  = A traffic roundabout directing cars to the right building
  Route53              = Road signs and GPS (translates names to addresses)
  ACM Certificates     = Official building permits (proves legitimacy)
  Security Groups      = Door locks on each building
  NACLs                = Neighborhood-level checkpoints
  VPC Endpoints        = Underground utility tunnels (water, power -- private, efficient)
  IAM Roles            = Employee badges with specific access levels
  CloudWatch           = City surveillance cameras and alarm systems
  S3                   = Warehouses on the outskirts of town
  ECR                  = The employee uniform warehouse (container images)
```

---

## 14. Explain Like I'm 5 (ELI5) Section

These explanations are designed to be understood by anyone, regardless of
technical background. Use them when explaining concepts to non-technical
stakeholders or when you need to check your own understanding.

### Terraform

```
  "Building with Lego, but the computer builds for you."

  You write a list:   "I want 3 red blocks, 2 blue blocks, 1 yellow block."
  The computer reads:  "OK, let me check what you already have..."
  The computer says:   "You have 2 red blocks. I need to add 1 more red block."
  You say:             "Go ahead!"
  The computer builds: *adds 1 red block*
  The computer notes:  "Done. You now have 3 red, 2 blue, 1 yellow."

  Next time, if you change the list to "3 red, 2 BLUE, 1 GREEN,"
  the computer only swaps the yellow for green. It does not rebuild everything.
```

### State File

```
  "A photo album of what you built."

  Every time the computer builds something, it takes a photo
  and puts it in an album. Next time you ask for changes,
  it looks at the album first:

    "Hmm, the photo shows 3 red blocks and 2 blue blocks.
     The new list says 4 red blocks and 2 blue blocks.
     I just need to add 1 red block!"

  If you lose the photo album, the computer gets confused:
    "I do not remember what I built! I might try to build
     everything again from scratch, and now you have duplicates."
```

### Providers

```
  "Different Lego sets: the AWS set, the Azure set, the Google set."

  Each set has different pieces and different instructions.
  Terraform knows how to use any set, but you have to tell it
  which one you are using:

    "Today I am using the AWS set."

  The AWS set has pieces called "VPC," "EC2," and "S3."
  The Azure set has pieces called "Resource Group," "VM," and "Blob Storage."
  Same idea, different names, different shapes.
```

### Modules

```
  "Pre-built Lego kits with instructions."

  Instead of building a castle brick by brick, you buy a
  "Castle Kit" that comes with instructions and all the pieces
  you need.

  In Terraform:
    - Someone already figured out the best way to build a VPC.
    - They packaged it as a "module" (a kit).
    - You just say: "I want the VPC kit, size Large, color Blue."
    - The module builds 20+ resources for you automatically.

  You can also make your OWN kits for things you build often.
```

### Plan

```
  "Showing your parents what you want to build before building it."

  Before you start snapping Lego pieces together, you draw a picture
  and show it to Mom or Dad:

    "I want to add a tower here and remove this wall."

  They look at it and say either:
    "Looks good, go ahead!"    --> terraform apply
    "Wait, that will knock over the whole castle!" --> fix the plan

  The plan never changes anything. It is just a preview.
```

### EKS (Elastic Kubernetes Service)

```
  "A playground manager that watches over all the kids (containers)."

  The playground (cluster) has a manager (control plane) who:
    - Decides where each kid (container) plays
    - Makes sure no kid is alone (replicas)
    - If a kid falls down (crashes), sends another kid to replace them
    - Opens more playground space (nodes) when too many kids show up
    - Closes extra space when kids go home

  You tell the manager: "I need 3 kids playing tag and 2 kids on swings."
  The manager handles the rest. You do not supervise each kid individually.
```

### VPC (Virtual Private Cloud)

```
  "Your yard with a fence around it."

  Your house has a yard with a big fence (VPC).
  Inside the fence, you have:
    - A front yard (public subnet): visitors can see it from the street
    - A backyard (private subnet): only family can go there
    - A locked shed (database subnet): only you have the key

  The front gate (Internet Gateway) lets people in from the street.
  The back gate (NAT Gateway) lets family members go to the store,
  but strangers cannot come in through the back gate.
```

### IAM (Identity and Access Management)

```
  "Name badges that say what rooms you can enter."

  At a big building, everyone wears a name badge.
  Your badge says:
    - Name: "Web Application"
    - Can enter: Storage Room (S3), Break Room (DynamoDB)
    - Cannot enter: Server Room (RDS), Boss's Office (IAM Admin)

  If you try to open a door your badge does not allow, it stays locked.
  The badge expires at the end of the day (temporary credentials),
  so even if someone finds it, they cannot use it forever.
```

---

## Quick Reference: Which Diagram to Use When

| Situation                              | Go To Section                          |
|----------------------------------------|----------------------------------------|
| "How does Terraform work?"             | Section 1 (Complete Picture)           |
| "What order does Terraform do things?" | Section 2 (Lifecycle Flow)             |
| "Why did resource X wait for Y?"       | Section 3 (Dependency Graph)           |
| "What is state and why does it matter?"| Section 4 (State Mental Model)         |
| "Explain the network architecture"     | Section 5 (VPC Architecture)           |
| "What does EKS actually look like?"    | Section 6 (EKS Deep Dive)             |
| "How does a request reach my app?"     | Section 7 (User to Pod Flow)           |
| "How do pods get AWS permissions?"     | Section 8 (IAM and IRSA)              |
| "How does deployment work?"            | Section 9 (CI/CD Pipeline)            |
| "How does scaling work?"              | Section 10 (Scaling)                   |
| "How much will this cost?"             | Section 11 (Cost Flow)                 |
| "Is this secure?"                      | Section 12 (Security Onion)            |
| "Show me everything at once"           | Section 13 (Complete Stack)            |
| "Explain it like I'm a beginner"       | Section 14 (ELI5)                      |

---

> **Next Steps**: Now that you can visualize every component, proceed to the
> hands-on implementation guides where you will build all of this yourself.
> Start with `01-fundamentals.md` if you have not already, or jump to
> `04-eks-production.md` to see the Terraform code behind these diagrams.
