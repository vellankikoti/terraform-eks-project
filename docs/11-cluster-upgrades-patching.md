# EKS Cluster Upgrades and Patching

## Table of Contents

1. [EKS Version Lifecycle](#eks-version-lifecycle)
2. [Pre-Upgrade Checklist](#pre-upgrade-checklist)
3. [Control Plane Upgrade Process](#control-plane-upgrade-process)
4. [Node Group Upgrade Strategies](#node-group-upgrade-strategies)
5. [EKS Addon Upgrades](#eks-addon-upgrades)
6. [Patch Management](#patch-management)
7. [Post-Upgrade Validation](#post-upgrade-validation)
8. [Rollback Procedures](#rollback-procedures)
9. [Terraform Patterns for Safe Upgrades](#terraform-patterns-for-safe-upgrades)
10. [Organizational Patterns](#organizational-patterns)
11. [Upgrade War Stories](#upgrade-war-stories)
12. [Quick Reference](#quick-reference)

---

## EKS Version Lifecycle

### How EKS Versioning Works

Amazon EKS follows upstream Kubernetes releases, typically lagging by a few weeks. Understanding the lifecycle is critical for planning upgrades.

```
Kubernetes upstream release
        |
        v (2-4 weeks)
EKS version available in preview
        |
        v (1-2 weeks)
EKS version Generally Available (GA)
        |
        v (14 months from GA)
Standard Support ends
        |
        v (12 months extended support)
Extended Support ends (extra cost: $0.60/hr per cluster)
        |
        v
Version no longer available - FORCED UPGRADE
```

### Support Timeline

| Phase | Duration | Cost | Details |
|-------|----------|------|---------|
| Standard Support | 14 months from GA | Included | Full support, patches, security fixes |
| Extended Support | 12 months after standard | +$0.60/hr (~$432/month) | Security patches only, no new features |
| End of Life | N/A | N/A | Automatic upgrade to next supported version |

### Version History (Recent)

| Version | GA Date | Standard End | Extended End | Key Features |
|---------|---------|-------------|-------------|--------------|
| 1.28 | Sep 2023 | Nov 2024 | Nov 2025 | Sidecar containers GA |
| 1.29 | Jan 2024 | Mar 2025 | Mar 2026 | KMS v2 GA, nftables |
| 1.30 | May 2024 | Jul 2025 | Jul 2026 | Contextual logging, CEL admission |
| 1.31 | Sep 2024 | Nov 2025 | Nov 2026 | AppArmor GA, Pod lifecycle improvements |

### Upgrade Constraints

- **One minor version at a time**: You cannot skip versions (1.29 -> 1.31 is NOT allowed)
- **Control plane first**: Always upgrade the control plane before nodes
- **No downgrade**: Control plane version cannot be rolled back once upgraded
- **N-2 skew**: Nodes can be up to 2 minor versions behind the control plane
- **Addon compatibility**: EKS managed addons have version-specific compatibility

---

## Pre-Upgrade Checklist

### Critical: Do These Before Every Upgrade

```bash
# 1. Check current versions
aws eks describe-cluster --name $CLUSTER --query 'cluster.version'
kubectl get nodes -o custom-columns=NAME:.metadata.name,VERSION:.status.nodeInfo.kubeletVersion

# 2. Review the Kubernetes changelog for breaking changes
# https://kubernetes.io/blog/  (search for "changes" in the target version)
# https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions.html

# 3. Check deprecated API usage
kubectl get --raw /metrics | grep apiserver_requested_deprecated_apis

# 4. Verify PodDisruptionBudgets won't block drains
kubectl get pdb --all-namespaces -o json | \
  jq '.items[] | select(.status.disruptionsAllowed == 0) | .metadata.name'

# 5. Check node health
kubectl get nodes
kubectl top nodes

# 6. Verify all pods are healthy
kubectl get pods --all-namespaces | grep -v "Running\|Completed"

# 7. Check EKS addon compatibility
for addon in vpc-cni coredns kube-proxy; do
  echo "=== $addon ==="
  aws eks describe-addon-versions \
    --addon-name $addon \
    --kubernetes-version TARGET_VERSION \
    --query 'addons[0].addonVersions[0]'
done

# 8. Backup etcd (EKS manages this, but verify)
# EKS automatically backs up etcd - but save your Terraform state
terraform state pull > backup-$(date +%Y%m%d).tfstate

# 9. Check Helm chart compatibility
helm list --all-namespaces
# Review each chart's docs for K8s version compatibility

# 10. Notify stakeholders
# - Platform team
# - Application teams with workloads on the cluster
# - On-call rotation
```

### Deprecated API Checklist by Version

When upgrading, these APIs are commonly affected:

**1.29 Notable Changes:**
- `flowcontrol.apiserver.k8s.io/v1beta2` removed (use `v1beta3` or `v1`)
- `node.k8s.io/v1beta1` RuntimeClass removed (use `node.k8s.io/v1`)

**1.30 Notable Changes:**
- CSI migration for in-tree volumes fully GA
- `SecurityContextDeny` admission plugin removed

**1.31 Notable Changes:**
- `PersistentVolumeLabel` admission controller removed
- `AppArmor` profiles via annotations deprecated (use field-based)

### Testing Strategy Before Upgrade

```
1. Upgrade dev first (lowest risk)
   - Run automated tests
   - Manual smoke tests
   - Wait 2-3 days

2. Upgrade staging (mirrors production)
   - Full integration test suite
   - Performance/load tests
   - Wait 1 week minimum

3. Upgrade production (highest risk)
   - During maintenance window
   - With rollback plan ready
   - Engineering team on standby
```

---

## Control Plane Upgrade Process

### How EKS Control Plane Upgrades Work

EKS manages the control plane as a service. When you trigger an upgrade:

```
[You trigger upgrade]
        |
        v
[EKS creates new control plane instances with new version]
        |
        v
[EKS runs health checks on new instances]
        |
        v
[EKS switches traffic to new instances]
        |
        v
[EKS terminates old instances]
        |
        v
[Upgrade complete - cluster is ACTIVE]
```

**Key behaviors:**
- The API server remains available during the upgrade (rolling update)
- Brief periods of API server unavailability are possible (seconds, not minutes)
- Existing workloads continue running uninterrupted
- The upgrade typically takes 15-30 minutes
- You cannot cancel an in-progress upgrade

### Using the Upgrade Script

```bash
# Preview what the upgrade will do
./scripts/upgrade-cluster.sh dev --dry-run

# Upgrade dev to next minor version
./scripts/upgrade-cluster.sh dev

# Upgrade staging to a specific version
./scripts/upgrade-cluster.sh staging 1.31

# Upgrade production (will prompt for confirmation)
./scripts/upgrade-cluster.sh prod 1.31
```

### Manual Control Plane Upgrade via AWS CLI

```bash
CLUSTER="myapp-prod"
TARGET_VERSION="1.31"

# Start the upgrade
aws eks update-cluster-version \
  --name $CLUSTER \
  --kubernetes-version $TARGET_VERSION

# Monitor progress
aws eks describe-update \
  --name $CLUSTER \
  --update-id <update-id-from-above>

# Wait for completion
aws eks wait cluster-active --name $CLUSTER

# Verify
aws eks describe-cluster --name $CLUSTER --query 'cluster.version'
```

### Terraform-based Control Plane Upgrade

```hcl
# In variables.tf, update the version
variable "cluster_version" {
  default = "1.31"  # Changed from "1.30"
}

# Then plan and apply
# terraform plan   - Review changes
# terraform apply  - Apply upgrade
```

**Important:** Terraform will show the cluster as needing replacement if version changes. EKS handles this as an in-place update, NOT a replacement. The Terraform AWS provider correctly performs `aws eks update-cluster-version` behind the scenes.

---

## Node Group Upgrade Strategies

### Strategy 1: Managed Node Group Rolling Update (Recommended)

This is the default strategy when using EKS managed node groups. EKS handles the entire process.

```
[Trigger node group update]
        |
        v
[EKS launches new nodes with updated AMI/version]
        |
        v
[EKS cordons old nodes (no new pods scheduled)]
        |
        v
[EKS drains old nodes (evicts pods respecting PDBs)]
        |
        v
[EKS terminates old nodes after drain completes]
        |
        v
[Repeat for each node, respecting maxUnavailable]
```

```bash
# Trigger rolling update
aws eks update-nodegroup-version \
  --cluster-name myapp-prod \
  --nodegroup-name system \
  --kubernetes-version 1.31

# Monitor progress
aws eks describe-nodegroup \
  --cluster-name myapp-prod \
  --nodegroup-name system \
  --query 'nodegroup.{status:status,version:version}'
```

**Configuration in Terraform:**

```hcl
node_groups = {
  system = {
    # ...
    max_unavailable = 1  # Only replace one node at a time
  }
}
```

**How `maxUnavailable` affects upgrade speed:**

| maxUnavailable | Nodes | Behavior | Risk |
|---------------|-------|----------|------|
| 1 | 3 | One at a time, safest | Slow (45-90 min for 3 nodes) |
| 2 | 6 | Two at a time | Moderate speed, some capacity reduction |
| 33% | 6 | Two at a time (percentage) | Same as above |

### Strategy 2: Blue-Green Node Group

Create a new node group alongside the old one, then decommission the old one.

```
[Phase 1: Create green node group]
  - New node group with updated version
  - Same instance types, sizes
  - Pods start scheduling on new nodes

[Phase 2: Cordon blue node group]
  - kubectl cordon each old node
  - No new pods on old nodes

[Phase 3: Drain blue node group]
  - kubectl drain each old node
  - Pods move to green nodes

[Phase 4: Remove blue node group]
  - Delete old node group
  - Clean up launch templates
```

```bash
# Phase 1: Create green node group (add in Terraform)
# Phase 2 & 3: Cordon and drain
for node in $(kubectl get nodes -l eks.amazonaws.com/nodegroup=system-blue -o name); do
  kubectl cordon $node
  kubectl drain $node --ignore-daemonsets --delete-emptydir-data --timeout=300s
done

# Phase 4: Remove blue node group from Terraform and apply
```

**When to use blue-green:**
- Production clusters with zero-downtime requirements
- When you need instant rollback capability
- When testing new instance types simultaneously
- When PDBs are too restrictive for rolling updates

### Strategy 3: Surge Upgrade

Temporarily increase capacity, then drain old nodes.

```hcl
# Step 1: Increase min/desired to add capacity
node_groups = {
  system = {
    desired_size = 6   # Was 3
    max_size     = 8   # Was 4
    min_size     = 6   # Was 3
  }
}

# Step 2: After new nodes are running, drain old nodes
# Step 3: Scale back down
```

---

## EKS Addon Upgrades

### Addon Compatibility Matrix

EKS managed addons must be compatible with your cluster version. Here is how to check:

```bash
# List compatible versions for each addon
for addon in vpc-cni coredns kube-proxy aws-ebs-csi-driver aws-efs-csi-driver; do
  echo "=== $addon ==="
  aws eks describe-addon-versions \
    --addon-name $addon \
    --kubernetes-version 1.31 \
    --query 'addons[0].addonVersions[:3].{version:addonVersion,default:compatibilities[0].defaultVersion}' \
    --output table
done
```

### VPC CNI (amazon-vpc-cni-k8s)

The VPC CNI plugin manages pod networking. It assigns VPC IP addresses directly to pods.

**Upgrade considerations:**
- VPC CNI is **backward and forward compatible** (more flexible than other addons)
- Can be upgraded independently of the cluster version
- New versions add features (prefix delegation, security groups for pods)
- Upgrading does NOT disrupt existing pod networking

```bash
# Check current version
aws eks describe-addon --cluster-name $CLUSTER --addon-name vpc-cni

# Get latest compatible version
aws eks describe-addon-versions \
  --addon-name vpc-cni \
  --kubernetes-version 1.31 \
  --query 'addons[0].addonVersions[0].addonVersion'

# Update
aws eks update-addon \
  --cluster-name $CLUSTER \
  --addon-name vpc-cni \
  --addon-version $VERSION \
  --resolve-conflicts OVERWRITE
```

### CoreDNS

CoreDNS provides cluster DNS resolution. Every pod relies on it.

**Upgrade considerations:**
- CoreDNS version MUST match the cluster version
- Always upgrade CoreDNS AFTER control plane upgrade
- Brief DNS resolution failures possible during rollout
- Use `podDisruptionBudget` to ensure at least one replica is always available

```bash
# Check current version
kubectl get deployment coredns -n kube-system -o jsonpath='{.spec.template.spec.containers[0].image}'

# Update via EKS addon
aws eks update-addon \
  --cluster-name $CLUSTER \
  --addon-name coredns \
  --addon-version $VERSION \
  --resolve-conflicts OVERWRITE
```

### kube-proxy

kube-proxy maintains network rules on nodes for Service routing.

**Upgrade considerations:**
- kube-proxy version should match the cluster version
- Runs as a DaemonSet on every node
- Rolling update - one node at a time
- Brief networking blips possible on individual nodes during update

```bash
# Update via EKS addon
aws eks update-addon \
  --cluster-name $CLUSTER \
  --addon-name kube-proxy \
  --addon-version $VERSION \
  --resolve-conflicts OVERWRITE
```

### Helm-based Addon Upgrades

For addons installed via Helm (Prometheus, Grafana, ArgoCD, etc.):

```bash
# List current Helm releases
helm list --all-namespaces

# Check for updates
helm repo update

# Upgrade a release
helm upgrade prometheus prometheus-community/kube-prometheus-stack \
  -n monitoring \
  --reuse-values \
  --version 55.5.0

# Rollback if needed
helm rollback prometheus 1 -n monitoring
```

### Addon Upgrade Order

Always upgrade addons in this order after a control plane upgrade:

```
1. kube-proxy      (network rules - low risk)
2. VPC CNI         (pod networking - low risk, backward compatible)
3. CoreDNS         (DNS - medium risk, brief blips possible)
4. EBS CSI Driver  (storage - low risk, only affects new PVCs)
5. EFS CSI Driver  (shared storage - low risk)
6. All other addons (Helm-managed, can be done in any order)
```

---

## Patch Management

### AMI Updates

EKS-optimized AMIs are updated regularly with:
- OS security patches (Amazon Linux 2 / Bottlerocket)
- Kubelet updates
- Container runtime updates
- AWS-specific patches

```bash
# Check latest EKS-optimized AMI
aws ssm get-parameter \
  --name "/aws/service/eks/optimized-ami/1.31/amazon-linux-2/recommended/image_id" \
  --query 'Parameter.Value' --output text

# Check AMI release version
aws ssm get-parameter \
  --name "/aws/service/eks/optimized-ami/1.31/amazon-linux-2/recommended/release_version" \
  --query 'Parameter.Value' --output text
```

### Using the Patch Script

```bash
# Patch all node groups in dev
./scripts/patch-nodes.sh dev

# Patch a specific node group in staging
./scripts/patch-nodes.sh staging system

# Preview what would happen in prod
./scripts/patch-nodes.sh prod --dry-run
```

### Patching Frequency Recommendations

| Environment | Frequency | Approach |
|------------|-----------|----------|
| Dev | Weekly (or on-demand) | Aggressive - patch immediately |
| Staging | Bi-weekly | After dev validation |
| Production | Monthly | After staging validation, during maintenance window |
| Security Critical | Immediately | All environments, expedited process |

### Security Patch Process

When a CVE is announced affecting your EKS nodes:

```
1. Assess severity (CVSS score, exploitability, blast radius)
2. Check if new AMI is available with the fix
3. Test in dev (automated if possible)
4. Apply to staging
5. Apply to production
   - For CRITICAL (CVSS 9.0+): Same day, expedited
   - For HIGH (CVSS 7.0-8.9): Within 72 hours
   - For MEDIUM: Next maintenance window
   - For LOW: Next regular patch cycle
```

### Bottlerocket vs Amazon Linux 2

| Feature | Amazon Linux 2 | Bottlerocket |
|---------|---------------|-------------|
| SSH access | Yes (default) | No (by design) |
| Package manager | yum | None (read-only root) |
| Update mechanism | Replace AMI | In-place API update |
| Security posture | Good | Better (minimal attack surface) |
| Custom software | Supported | Not recommended |
| Troubleshooting | Easier (SSH) | Harder (admin container) |
| EKS default | Yes | No (opt-in) |

---

## Post-Upgrade Validation

### Automated Validation Checklist

Run these checks after every upgrade:

```bash
#!/bin/bash
# Post-upgrade validation script

echo "=== 1. Cluster Version ==="
aws eks describe-cluster --name $CLUSTER --query 'cluster.version'

echo "=== 2. Cluster Status ==="
aws eks describe-cluster --name $CLUSTER --query 'cluster.status'

echo "=== 3. Node Versions ==="
kubectl get nodes -o custom-columns=\
NAME:.metadata.name,\
VERSION:.status.nodeInfo.kubeletVersion,\
OS:.status.nodeInfo.osImage,\
RUNTIME:.status.nodeInfo.containerRuntimeVersion

echo "=== 4. System Pod Health ==="
kubectl get pods -n kube-system --no-headers | grep -v "Running\|Completed"

echo "=== 5. All Pod Health ==="
kubectl get pods --all-namespaces --no-headers | grep -v "Running\|Completed" | head -20

echo "=== 6. DNS Resolution Test ==="
kubectl run dns-test --image=busybox:1.36 --restart=Never --rm -it \
  -- nslookup kubernetes.default.svc.cluster.local

echo "=== 7. Service Connectivity ==="
kubectl get svc --all-namespaces | grep -v "ClusterIP"

echo "=== 8. PersistentVolume Status ==="
kubectl get pv | grep -v "Bound\|Available"

echo "=== 9. EKS Addon Status ==="
for addon in $(aws eks list-addons --cluster-name $CLUSTER --query 'addons[]' --output text); do
  STATUS=$(aws eks describe-addon --cluster-name $CLUSTER --addon-name $addon --query 'addon.status' --output text)
  VERSION=$(aws eks describe-addon --cluster-name $CLUSTER --addon-name $addon --query 'addon.addonVersion' --output text)
  echo "  $addon: $STATUS ($VERSION)"
done

echo "=== 10. Node Group Status ==="
for ng in $(aws eks list-nodegroups --cluster-name $CLUSTER --query 'nodegroups[]' --output text); do
  STATUS=$(aws eks describe-nodegroup --cluster-name $CLUSTER --nodegroup-name $ng --query 'nodegroup.status' --output text)
  VERSION=$(aws eks describe-nodegroup --cluster-name $CLUSTER --nodegroup-name $ng --query 'nodegroup.version' --output text)
  echo "  $ng: $STATUS (k8s $VERSION)"
done
```

### Application-level Validation

Beyond infrastructure checks, validate your applications:

```bash
# Check application health endpoints
curl -s https://app.example.com/health | jq .

# Run smoke tests
./tests/smoke-test.sh

# Check application metrics in Grafana
# - Request latency (should not increase)
# - Error rate (should not spike)
# - Pod restart count (should be 0)

# Check application logs for errors
kubectl logs -l app=myapp --tail=100 --since=30m | grep -i error
```

---

## Rollback Procedures

### Important: What Can and Cannot Be Rolled Back

| Component | Rollback Possible? | Method |
|-----------|-------------------|--------|
| Control plane version | NO | Cannot downgrade EKS control plane |
| Node group AMI | YES | Update launch template to previous AMI |
| Node group K8s version | YES | Create new node group at old version |
| EKS managed addons | YES | Update to previous compatible version |
| Helm releases | YES | `helm rollback <release> <revision>` |
| Terraform state | YES | Restore from backup |

### Control Plane Rollback (Not Possible)

The EKS control plane cannot be downgraded. If an upgrade causes issues:

1. **Fix forward**: Address compatibility issues in your workloads
2. **Keep old node version**: Nodes can be N-2 behind the control plane
3. **Create new cluster**: As a last resort, create a new cluster at the old version and migrate workloads

### Node Group Rollback

```bash
# Option 1: Update node group to previous AMI
# Find previous AMI from launch template versions
aws ec2 describe-launch-template-versions \
  --launch-template-name eks-$CLUSTER-system \
  --query 'LaunchTemplateVersions[*].{Version:VersionNumber,AMI:LaunchTemplateData.ImageId}'

# Update to previous version
aws ec2 create-launch-template-version \
  --launch-template-name eks-$CLUSTER-system \
  --source-version 2 \
  --launch-template-data '{"ImageId":"ami-previous"}'

# Option 2: Create new node group at old version
aws eks create-nodegroup \
  --cluster-name $CLUSTER \
  --nodegroup-name system-rollback \
  --kubernetes-version 1.30 \
  ...
```

### Helm Release Rollback

```bash
# List release history
helm history prometheus -n monitoring

# Rollback to previous revision
helm rollback prometheus 5 -n monitoring

# Verify
helm status prometheus -n monitoring
```

### Terraform State Rollback

```bash
# If Terraform state is corrupted or wrong
# Restore from backup
cp .state-backups/prod/terraform.tfstate.pre-upgrade.20240101-120000 \
   terraform/environments/prod/terraform.tfstate

# Or if using remote state (S3)
aws s3 cp s3://my-terraform-state/prod/terraform.tfstate.backup terraform.tfstate
terraform state push terraform.tfstate
```

---

## Terraform Patterns for Safe Upgrades

### Pattern 1: Version Variable with Validation

```hcl
variable "cluster_version" {
  description = "Kubernetes version for EKS cluster"
  type        = string
  default     = "1.31"

  validation {
    condition     = can(regex("^1\\.(2[8-9]|3[0-9])$", var.cluster_version))
    error_message = "Cluster version must be a supported EKS version (1.28+)."
  }
}
```

### Pattern 2: Lifecycle Ignore for Controlled Upgrades

```hcl
resource "aws_eks_cluster" "main" {
  name    = var.cluster_name
  version = var.cluster_version

  # Prevent Terraform from reverting manual upgrades
  lifecycle {
    ignore_changes = [version]
  }
}
```

Use this when you upgrade via CLI/console and want Terraform to not fight you.

### Pattern 3: Separate Node Group Resources for Blue-Green

```hcl
# Blue (current)
resource "aws_eks_node_group" "system_blue" {
  count           = var.active_node_group == "blue" ? 1 : 0
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "system-blue"
  # ...
}

# Green (new version)
resource "aws_eks_node_group" "system_green" {
  count           = var.active_node_group == "green" ? 1 : 0
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "system-green"
  # ...
}

variable "active_node_group" {
  default = "blue"  # Toggle to "green" during upgrade
}
```

### Pattern 4: Prevent Accidental Destruction

```hcl
resource "aws_eks_cluster" "main" {
  # ...

  lifecycle {
    prevent_destroy = true  # Requires explicit removal before destroy
  }
}
```

### Pattern 5: Terraform Plan Gate

Always run `terraform plan` before `terraform apply` during upgrades:

```bash
# Generate plan
terraform plan -out=upgrade.plan -var="cluster_version=1.31"

# Review plan carefully - look for:
# - "forces replacement" (BAD for clusters - should be in-place update)
# - Unexpected resource deletions
# - Security group changes

# Apply only the reviewed plan
terraform apply upgrade.plan
```

### Pattern 6: State Backup Before Upgrade

```bash
# Before any upgrade
terraform state pull > "backup-$(date +%Y%m%d-%H%M%S).tfstate"

# After upgrade, if state is broken
terraform state push backup-20240101-120000.tfstate
```

---

## Organizational Patterns

### Upgrade Cadence

Most organizations follow one of these patterns:

**Conservative (Enterprise/Regulated):**
- Upgrade every 2-3 months
- Stay on N-1 version (one behind latest)
- Full change management process
- Maintenance windows on weekends

**Moderate (Standard):**
- Upgrade every 1-2 months
- Stay current or N-1
- Streamlined approval process
- Maintenance windows during low-traffic periods

**Aggressive (Startup/Cloud-Native):**
- Upgrade within weeks of GA
- Stay on latest version
- Automated upgrade pipelines
- No maintenance windows (zero-downtime rolling upgrades)

### Communication Plan

```
Timeline for Production Upgrade:

T-14 days: Announce upgrade plan to all stakeholders
T-7  days: Dev cluster upgraded, testing begins
T-5  days: Staging cluster upgraded, integration tests
T-3  days: Send reminder with upgrade window details
T-1  day:  Final go/no-go decision
T-0:       Production upgrade during maintenance window
T+1  day:  Post-upgrade monitoring, all-clear notification
T+7  days: Retrospective (if issues occurred)
```

### Runbook Template

```markdown
## EKS Upgrade Runbook: 1.30 -> 1.31

### Pre-requisites
- [ ] Changelog reviewed for breaking changes
- [ ] Dev upgraded and tested (link to test results)
- [ ] Staging upgraded and tested (link to test results)
- [ ] PDB audit complete
- [ ] Deprecated API audit complete
- [ ] Addon compatibility verified
- [ ] Terraform state backed up
- [ ] Stakeholders notified
- [ ] On-call engineer identified: ___________

### Execution
- [ ] Control plane upgrade initiated
- [ ] Control plane upgrade complete (time: ___)
- [ ] Node group 'system' upgraded
- [ ] Node group 'general' upgraded
- [ ] Node group 'spot' upgraded
- [ ] EKS addons updated (vpc-cni, coredns, kube-proxy)
- [ ] Helm releases updated (if needed)

### Validation
- [ ] All nodes at target version
- [ ] All system pods healthy
- [ ] DNS resolution working
- [ ] Application health checks passing
- [ ] Metrics flowing to Prometheus
- [ ] Logs flowing to log aggregator
- [ ] No elevated error rates

### Sign-off
- Upgraded by: ___________
- Validated by: ___________
- Date/Time: ___________
```

### Multi-cluster Upgrade Order

If you manage multiple clusters:

```
1. Dev cluster (lowest risk)
   - Automated upgrade + tests
   - Wait 2-3 days

2. Staging cluster (prod mirror)
   - Full test suite
   - Wait 1 week

3. Non-critical production clusters
   - Batch upgrade during maintenance
   - Wait 1 week

4. Critical production clusters
   - One at a time
   - Full monitoring between each
```

---

## Upgrade War Stories

### War Story 1: The CoreDNS Crash

**What happened:** After upgrading from 1.28 to 1.29, CoreDNS pods kept crash-looping. All DNS resolution in the cluster failed, taking down every application.

**Root cause:** A custom CoreDNS ConfigMap had been applied that was incompatible with the new CoreDNS version. The `--resolve-conflicts OVERWRITE` flag was not used, so the addon update failed silently.

**Lesson learned:**
- Always use `--resolve-conflicts OVERWRITE` for EKS addon updates
- Keep CoreDNS configuration in Terraform, not applied manually
- Monitor CoreDNS pod health immediately after upgrade
- Have a `kubectl apply` ready to restore the default CoreDNS config

### War Story 2: PDB Deadlock During Node Drain

**What happened:** During a production node group upgrade, the rolling update got stuck. One node had been cordoned for 2 hours but could not be drained. The cluster was in a degraded state with reduced capacity.

**Root cause:** A PDB required `minAvailable: 2` but the Deployment only had 2 replicas. With the node cordoned, only 1 replica was available on a healthy node, so the PDB prevented the second pod from being evicted.

**Lesson learned:**
- Audit PDBs before every upgrade: `kubectl get pdb --all-namespaces`
- PDB `minAvailable` should always be less than `replicas - maxUnavailable`
- Use `maxUnavailable` in PDBs instead of `minAvailable` when possible
- For rolling node updates, ensure pods can be rescheduled to other nodes

### War Story 3: The Spot Instance Stampede

**What happened:** After upgrading a spot node group, all spot instances were terminated simultaneously instead of being rolled one at a time. Application availability dropped to zero for several minutes.

**Root cause:** The spot instances received termination notices from AWS (unrelated to the upgrade) during the rolling update. Combined with the upgrade-related replacements, all nodes went down at once.

**Lesson learned:**
- Schedule upgrades during off-peak hours when spot interruption rates are lower
- Ensure on-demand node groups have enough capacity for critical workloads
- Use `topologySpreadConstraints` to spread pods across node groups
- Consider upgrading spot and on-demand node groups separately

### War Story 4: Terraform State Drift

**What happened:** An engineer upgraded the production cluster via the AWS console (not Terraform). The next `terraform plan` showed the cluster would be "updated" back to the old version.

**Root cause:** Terraform state still had the old version. Running `terraform apply` would have downgraded the cluster (which EKS would reject, but the plan was alarming).

**Lesson learned:**
- Always upgrade through Terraform or update Terraform variables immediately after manual upgrade
- Use `lifecycle { ignore_changes = [version] }` if upgrades happen outside Terraform
- Run `terraform refresh` after any out-of-band changes
- Document the upgrade process and ensure everyone follows it

### War Story 5: Webhook Certificates Expired During Upgrade

**What happened:** After upgrading to 1.30, all pod creations failed with `webhook connection refused` errors. New deployments and scaling events were completely blocked.

**Root cause:** Cert-manager's webhook certificates had expired, and the upgrade process restarted cert-manager before its self-signed certificates were renewed. The admission webhook rejected all API calls.

**Lesson learned:**
- Check cert-manager certificate expiry before upgrades: `kubectl get certificates --all-namespaces`
- Renew certificates before upgrading: `cmctl renew --all --all-namespaces`
- Consider adding `failurePolicy: Ignore` to non-critical webhooks during upgrade windows
- Monitor webhook health as part of post-upgrade validation

---

## Quick Reference

### Upgrade Commands Cheat Sheet

```bash
# === PRE-UPGRADE ===
# Check current version
aws eks describe-cluster --name $CLUSTER --query 'cluster.version'

# Check available versions
aws eks describe-addon-versions --query 'addons[0].addonVersions[*].compatibilities[*].clusterVersion' --output text | tr '\t' '\n' | sort -uV

# Backup state
terraform state pull > backup-$(date +%Y%m%d).tfstate

# === UPGRADE CONTROL PLANE ===
aws eks update-cluster-version --name $CLUSTER --kubernetes-version $VERSION
aws eks wait cluster-active --name $CLUSTER

# === UPGRADE NODE GROUPS ===
aws eks update-nodegroup-version --cluster-name $CLUSTER --nodegroup-name $NG --kubernetes-version $VERSION
aws eks wait nodegroup-active --cluster-name $CLUSTER --nodegroup-name $NG

# === UPGRADE ADDONS ===
aws eks update-addon --cluster-name $CLUSTER --addon-name vpc-cni --addon-version $V --resolve-conflicts OVERWRITE
aws eks update-addon --cluster-name $CLUSTER --addon-name coredns --addon-version $V --resolve-conflicts OVERWRITE
aws eks update-addon --cluster-name $CLUSTER --addon-name kube-proxy --addon-version $V --resolve-conflicts OVERWRITE

# === VALIDATE ===
kubectl get nodes -o wide
kubectl get pods --all-namespaces | grep -v Running
kubectl run dns-test --image=busybox:1.36 --rm -it -- nslookup kubernetes.default

# === PATCH NODES ===
aws eks update-nodegroup-version --cluster-name $CLUSTER --nodegroup-name $NG --release-version $RELEASE
```

### Environment Upgrade Order

```
dev -> staging -> prod
 |        |         |
 v        v         v
 2-3d    1 week    production
 wait    wait      maintenance
                   window
```

### Emergency Contacts Template

```
EKS Upgrade Emergency Contacts:
- Platform Lead: ___________
- On-call Engineer: ___________
- AWS Support Case: ___________
- Slack Channel: #platform-upgrades
- PagerDuty Service: EKS Cluster
```

### Useful Links

- [EKS Version Support](https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions.html)
- [EKS Upgrade Guide](https://docs.aws.amazon.com/eks/latest/userguide/update-cluster.html)
- [Kubernetes Changelog](https://github.com/kubernetes/kubernetes/blob/master/CHANGELOG/)
- [EKS Best Practices Guide](https://aws.github.io/aws-eks-best-practices/)
- [EKS Addon Versions](https://docs.aws.amazon.com/eks/latest/userguide/managing-add-ons.html)
