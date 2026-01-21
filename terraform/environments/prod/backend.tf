# Backend Configuration for Remote State
# Uncomment and configure after creating S3 bucket and DynamoDB table

# terraform {
#   backend "s3" {
#     bucket         = "myapp-terraform-state"
#     key            = "prod/terraform.tfstate"
#     region         = "us-east-1"
#     dynamodb_table = "terraform-locks"
#     encrypt        = true
#   }
# }

# To create the backend resources, run this first:
#
# aws s3api create-bucket \
#   --bucket myapp-terraform-state \
#   --region us-east-1
#
# aws s3api put-bucket-versioning \
#   --bucket myapp-terraform-state \
#   --versioning-configuration Status=Enabled
#
# aws s3api put-bucket-encryption \
#   --bucket myapp-terraform-state \
#   --server-side-encryption-configuration '{
#     "Rules": [{
#       "ApplyServerSideEncryptionByDefault": {
#         "SSEAlgorithm": "AES256"
#       }
#     }]
#   }'
#
# aws dynamodb create-table \
#   --table-name terraform-locks \
#   --attribute-definitions AttributeName=LockID,AttributeType=S \
#   --key-schema AttributeName=LockID,KeyType=HASH \
#   --billing-mode PAY_PER_REQUEST \
#   --region us-east-1
