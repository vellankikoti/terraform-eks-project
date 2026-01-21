# VPC Module

Production-grade, multi-AZ VPC for EKS clusters.

## Features

- ✅ Multi-AZ architecture (2-6 AZs)
- ✅ Public and private subnets
- ✅ Optional database subnets
- ✅ NAT Gateways (one per AZ for HA)
- ✅ Internet Gateway
- ✅ Proper EKS subnet tagging
- ✅ VPC Flow Logs (optional)
- ✅ VPC Endpoints for S3, DynamoDB, ECR (optional, reduces NAT costs)
- ✅ Cost-optimized defaults

## Usage

```hcl
module "vpc" {
  source = "../../modules/vpc"

  name_prefix  = "production"
  vpc_cidr     = "10.0.0.0/16"
  az_count     = 2
  cluster_name = "production-eks"
  aws_region   = "us-east-1"

  enable_nat_gateway       = true
  create_database_subnets  = true
  enable_flow_logs         = true
  enable_s3_endpoint       = true
  enable_dynamodb_endpoint = true
  enable_ecr_endpoints     = false  # Costs ~$7/month per AZ

  tags = {
    Environment = "production"
    ManagedBy   = "terraform"
  }
}
```

## CIDR Allocation

For `vpc_cidr = "10.0.0.0/16"` and `az_count = 2`:

| Subnet Type | AZ | CIDR | IPs | Purpose |
|-------------|----|----- |-----|---------|
| Public | us-east-1a | 10.0.0.0/24 | 251 | NAT GW, ALB |
| Public | us-east-1b | 10.0.1.0/24 | 251 | NAT GW, ALB |
| Private | us-east-1a | 10.0.10.0/24 | 251 | EKS nodes |
| Private | us-east-1b | 10.0.11.0/24 | 251 | EKS nodes |
| Database | us-east-1a | 10.0.20.0/24 | 251 | RDS, ElastiCache |
| Database | us-east-1b | 10.0.21.0/24 | 251 | RDS, ElastiCache |

## Cost Considerations

| Resource | Monthly Cost (us-east-1) | Can Disable? |
|----------|-------------------------|--------------|
| NAT Gateway (per AZ) | ~$35 | No (for private subnets) |
| NAT Gateway data | ~$0.045/GB | No |
| VPC endpoints (interface) | ~$7 per endpoint | Yes (use for ECR only if needed) |
| VPC endpoints (gateway) | Free | No cost |
| VPC Flow Logs | ~$0.50/GB ingested | Yes (disable in dev) |

**Typical monthly cost**: $70-100 for 2 AZs with NAT Gateways.

## Outputs

- `vpc_id` - VPC identifier
- `public_subnet_ids` - List of public subnet IDs
- `private_subnet_ids` - List of private subnet IDs
- `database_subnet_ids` - List of database subnet IDs
- `nat_gateway_ids` - List of NAT Gateway IDs

## EKS Integration

This module automatically tags subnets for EKS:

- Public subnets: `kubernetes.io/role/elb = 1` (for public ALBs)
- Private subnets: `kubernetes.io/role/internal-elb = 1` (for internal NLBs)
- All subnets: `kubernetes.io/cluster/<cluster-name> = shared`

These tags are required for AWS Load Balancer Controller to discover subnets.
