# Spot Instances Example
# Demonstrates how to configure mixed instance types with spot for cost savings
#
# Best practices for spot instances on EKS:
# 1. Diversify across multiple instance types and families
# 2. Use capacity-optimized allocation strategy (AWS default for managed node groups)
# 3. Keep critical system workloads on ON_DEMAND instances
# 4. Use pod disruption budgets for graceful handling of spot interruptions
# 5. Spread across multiple AZs for better spot availability
#
# Usage:
#   This example shows the node_groups configuration to pass to the EKS module.
#   Copy and adapt the node_groups variable into your environment's terraform.tfvars.

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

locals {
  cluster_name = "${var.project_name}-${var.environment}"

  # -----------------------------------------------------------------------
  # Node Groups Configuration
  # -----------------------------------------------------------------------
  # This is the key configuration for mixed on-demand/spot instances.
  # The structure matches what the EKS module expects for var.node_groups.
  # -----------------------------------------------------------------------

  node_groups = {

    # -----------------------------------------------------------------------
    # System Node Group (ON_DEMAND)
    # -----------------------------------------------------------------------
    # Always use ON_DEMAND for system workloads:
    # - CoreDNS, kube-proxy, aws-node
    # - Cluster Autoscaler
    # - Monitoring agents (Prometheus, Datadog, etc.)
    # - Ingress controllers
    #
    # These workloads must remain available even during spot interruptions.
    # -----------------------------------------------------------------------
    system = {
      instance_types = ["t3.medium"]
      capacity_type  = "ON_DEMAND"

      scaling_config = {
        desired_size = 2
        min_size     = 2    # Always keep at least 2 for HA
        max_size     = 4
      }

      labels = {
        role     = "system"
        workload = "system"
      }

      taints = [
        {
          key    = "CriticalAddonsOnly"
          value  = "true"
          effect = "NO_SCHEDULE"    # Only pods that tolerate this taint will schedule here
        }
      ]
    }

    # -----------------------------------------------------------------------
    # General Purpose Spot Node Group
    # -----------------------------------------------------------------------
    # For general application workloads that can tolerate interruptions.
    #
    # Key spot best practices applied here:
    # - Multiple instance types across different families (t3, t3a, m5, m5a)
    #   This increases the spot capacity pool, reducing interruption frequency.
    # - All instances are roughly equivalent in CPU/memory so pods schedule
    #   consistently regardless of which type is available.
    # - t3a/m5a use AMD processors and are often cheaper with more availability.
    # -----------------------------------------------------------------------
    general-spot = {
      instance_types = [
        "t3.large",     # 2 vCPU, 8 GiB  - Intel
        "t3a.large",    # 2 vCPU, 8 GiB  - AMD (usually cheaper)
        "m5.large",     # 2 vCPU, 8 GiB  - Intel, general purpose
        "m5a.large",    # 2 vCPU, 8 GiB  - AMD, general purpose
      ]
      capacity_type = "SPOT"

      scaling_config = {
        desired_size = 3
        min_size     = 1    # Can scale down to 1 when idle
        max_size     = 10   # Scale up for peak load
      }

      labels = {
        role          = "general"
        workload      = "general"
        capacity-type = "spot"     # Useful for pod affinity rules
      }

      # No taints - general workloads can schedule freely
      taints = []
    }

    # -----------------------------------------------------------------------
    # Compute-Optimized Spot Node Group
    # -----------------------------------------------------------------------
    # For CPU-intensive workloads: data processing, batch jobs, CI/CD, ML inference.
    #
    # Uses compute-optimized instances (c5, c5a, c6i):
    # - Higher CPU-to-memory ratio than general purpose
    # - Better price/performance for CPU-bound workloads
    # - Multiple families for spot availability
    # -----------------------------------------------------------------------
    compute-spot = {
      instance_types = [
        "c5.xlarge",    # 4 vCPU, 8 GiB  - Intel, compute optimized
        "c5a.xlarge",   # 4 vCPU, 8 GiB  - AMD, compute optimized
        "c6i.xlarge",   # 4 vCPU, 8 GiB  - Intel Ice Lake, newer generation
      ]
      capacity_type = "SPOT"

      scaling_config = {
        desired_size = 0    # Scale from zero - only when needed
        min_size     = 0
        max_size     = 8
      }

      labels = {
        role          = "compute"
        workload      = "compute"
        capacity-type = "spot"
      }

      # Taint so only pods that explicitly request compute nodes schedule here
      taints = [
        {
          key    = "workload"
          value  = "compute"
          effect = "NO_SCHEDULE"
        }
      ]
    }
  }
}

# -----------------------------------------------------------------------
# Output the node_groups configuration
# Copy this into your environment's terraform.tfvars
# -----------------------------------------------------------------------

output "node_groups_config" {
  description = "Node groups configuration to use in your environment's terraform.tfvars"
  value       = local.node_groups
}

output "spot_usage_notes" {
  description = "Important notes about using spot instances"
  value       = <<-EOT

    Spot Instance Usage Notes:
    -------------------------
    1. Add PodDisruptionBudgets (PDBs) to your applications to handle spot interruptions gracefully.
    2. Use the 'capacity-type=spot' label with nodeAffinity or nodeSelector to target spot nodes.
    3. Critical workloads should tolerate the CriticalAddonsOnly taint to run on system nodes.
    4. Monitor spot interruption events: kubectl get events --field-selector reason=SpotInterruption
    5. Consider using the AWS Node Termination Handler for graceful spot instance shutdown.

    Example pod spec targeting spot nodes:
    --------------------------------------
      nodeSelector:
        capacity-type: spot
      tolerations:
        - key: "workload"
          value: "compute"
          effect: "NoSchedule"

    Example PodDisruptionBudget:
    ----------------------------
      apiVersion: policy/v1
      kind: PodDisruptionBudget
      metadata:
        name: my-app-pdb
      spec:
        minAvailable: "50%"
        selector:
          matchLabels:
            app: my-app
  EOT
}
