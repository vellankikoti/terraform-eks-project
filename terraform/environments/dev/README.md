# Development Environment

Production-grade EKS cluster for development workloads.

## Architecture

- **VPC**: 10.0.0.0/16 with 2 AZs
- **EKS**: Kubernetes 1.28
- **Node Groups**: 2 t3.medium nodes (auto-scales 1-5)
- **Add-ons**: AWS Load Balancer Controller, Cluster Autoscaler

## Prerequisites

1. AWS CLI configured
2. Terraform >= 1.6.0
3. kubectl
4. helm

## Estimated Monthly Cost

| Resource | Cost |
|----------|------|
| EKS Control Plane | $73 |
| EC2 Nodes (2x t3.medium) | ~$60 |
| NAT Gateways (2x) | ~$70 |
| EBS Volumes | ~$10 |
| **Total** | **~$213/month** |

To reduce costs in dev:
- Use 1 NAT Gateway instead of 2 (less HA)
- Use smaller instance types (t3.small)
- Use Spot instances for non-critical workloads
- Destroy environment when not in use

## Quick Start

### 1. Initialize Terraform

```bash
cd terraform/environments/dev
terraform init
```

### 2. Plan

```bash
terraform plan
```

Review the plan. You should see:
- VPC with subnets
- EKS cluster
- Node groups
- IAM roles
- Add-ons

### 3. Apply

```bash
terraform apply
```

This takes ~15-20 minutes.

### 4. Configure kubectl

```bash
aws eks update-kubeconfig --region us-east-1 --name myapp-dev
```

### 5. Verify

```bash
kubectl get nodes
kubectl get pods -A
```

You should see:
- 2 nodes in Ready state
- Pods in kube-system namespace (CoreDNS, aws-load-balancer-controller, cluster-autoscaler, etc.)

## Testing the Cluster

### Test 1: Deploy a Sample Application

```bash
kubectl create deployment nginx --image=nginx
kubectl expose deployment nginx --port=80 --type=LoadBalancer
kubectl get svc nginx
```

Wait for the LoadBalancer to be provisioned (AWS Load Balancer Controller creates an NLB).

### Test 2: Create an Ingress

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: nginx
  annotations:
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
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

Save as `ingress.yaml` and apply:

```bash
kubectl apply -f ingress.yaml
kubectl get ingress nginx
```

AWS Load Balancer Controller creates an ALB.

### Test 3: Test Cluster Autoscaler

```bash
# Deploy a workload that requires more nodes
kubectl create deployment scale-test --image=nginx --replicas=50

# Watch nodes scale up
kubectl get nodes -w

# Clean up
kubectl delete deployment scale-test

# Watch nodes scale down (takes ~10 minutes)
kubectl get nodes -w
```

## Updating the Cluster

### Update Kubernetes Version

1. Update `cluster_version` in `terraform.tfvars`
2. Run `terraform apply`
3. Update node groups (Terraform will replace nodes with rolling update)

### Add a Node Group

Edit `terraform.tfvars`:

```hcl
node_groups = {
  general = { ... }

  compute = {
    desired_size   = 1
    max_size       = 10
    min_size       = 0
    instance_types = ["c5.xlarge"]
    capacity_type  = "SPOT"
    labels = {
      role = "compute"
    }
  }
}
```

Run `terraform apply`.

## Destroy

**⚠️ WARNING: This deletes everything!**

```bash
terraform destroy
```

Confirm with `yes`.

## Troubleshooting

### Issue: Nodes not joining cluster

**Check:**
```bash
kubectl get nodes
aws eks describe-cluster --name myapp-dev --query 'cluster.status'
```

**Solution:** Check node IAM role has correct policies.

### Issue: Pods stuck in Pending

**Check:**
```bash
kubectl describe pod <pod-name>
```

**Common causes:**
- Insufficient CPU/memory (scale up)
- Image pull errors (check ECR permissions)
- Persistent volume issues (check EBS CSI driver)

### Issue: Load Balancer not created

**Check:**
```bash
kubectl logs -n kube-system deployment/aws-load-balancer-controller
```

**Common causes:**
- Subnets not tagged correctly (check VPC module tags)
- IAM permissions missing (check IRSA role)

## Next Steps

- Deploy your application
- Set up CI/CD with ArgoCD
- Configure monitoring (Prometheus, Grafana)
- Set up log aggregation (Fluent Bit → CloudWatch/S3)
- Configure alerting (Prometheus Alertmanager)

## References

- [EKS Best Practices](https://aws.github.io/aws-eks-best-practices/)
- [AWS Load Balancer Controller Docs](https://kubernetes-sigs.github.io/aws-load-balancer-controller/)
- [Cluster Autoscaler Docs](https://github.com/kubernetes/autoscaler/tree/master/cluster-autoscaler)
