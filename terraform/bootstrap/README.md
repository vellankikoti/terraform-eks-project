# Terraform Bootstrap - Remote State Backend

This module creates the S3 bucket and DynamoDB table required for Terraform remote state management. **Run this FIRST before any other Terraform code in this project.**

## What It Creates

| Resource | Purpose |
|----------|---------|
| S3 Bucket | Stores Terraform state files with versioning and encryption |
| DynamoDB Table | Provides state locking to prevent concurrent modifications |

## Prerequisites

- AWS CLI configured with appropriate credentials
- Terraform >= 1.6.0
- Your AWS Account ID (12-digit number)

## Step-by-Step Setup

### Step 1: Initialize and Apply Bootstrap

```bash
cd terraform/bootstrap
terraform init
terraform plan -var="aws_account_id=123456789012"
terraform apply -var="aws_account_id=123456789012"
```

Replace `123456789012` with your actual AWS Account ID. You can find it by running:

```bash
aws sts get-caller-identity --query Account --output text
```

### Step 2: Note the Outputs

After apply completes, Terraform will display the `backend_config` output. It will look like this:

```hcl
terraform {
  backend "s3" {
    bucket         = "myapp-terraform-state-123456789012"
    key            = "<environment>/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "myapp-terraform-locks"
    encrypt        = true
  }
}
```

### Step 3: Configure Environment Backends

Update the `backend.tf` file in each environment (`dev`, `staging`, `prod`) with the backend configuration from the output. Set the `key` to match the environment:

- **Dev:** `key = "dev/terraform.tfstate"`
- **Staging:** `key = "staging/terraform.tfstate"`
- **Prod:** `key = "prod/terraform.tfstate"`

### Step 4: Initialize Environments with Backend

```bash
cd ../environments/dev
terraform init
```

Terraform will detect the new backend and offer to migrate local state.

## Customization

You can override defaults using a `terraform.tfvars` file:

```hcl
aws_region     = "us-west-2"
project_name   = "myproject"
aws_account_id = "123456789012"
```

## Important Notes

- Both the S3 bucket and DynamoDB table have `prevent_destroy` lifecycle rules to avoid accidental deletion.
- S3 bucket versioning is enabled so you can recover previous state files.
- Old state file versions are automatically cleaned up after 90 days.
- The S3 bucket blocks all public access.
- The DynamoDB table uses PAY_PER_REQUEST billing (no cost when idle).
- This module uses **local state** by design -- it manages the backend that all other modules use.

## Destroying (Use with Extreme Caution)

If you truly need to destroy the backend resources, you must first remove the `prevent_destroy` lifecycle rules from `main.tf`, then run `terraform destroy`. This will permanently delete all stored state files.
