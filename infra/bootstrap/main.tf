# Bootstrap: Create the S3 bucket and DynamoDB table for Terraform remote state.
# Run this once before initializing any environment:
#
#   cd infra/bootstrap
#   terraform init          # local state — intentional
#   terraform apply
#
# Store the resulting terraform.tfstate in a secure location (e.g. 1Password / Vault).
# All subsequent environment state is stored in the S3 bucket created here.

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  # Bootstrap itself uses local state (no chicken-and-egg).
}

provider "aws" {
  region = "us-east-1"
}

# ─── KMS key for Terraform state bucket ──────────────────────────────────────

resource "aws_kms_key" "terraform_state" {
  description             = "CMK for Terraform state S3 bucket (AWS-0132)"
  deletion_window_in_days = 10
  enable_key_rotation     = true
}

resource "aws_kms_alias" "terraform_state" {
  name          = "alias/terraform-state"
  target_key_id = aws_kms_key.terraform_state.key_id
}

# ─── Access-log bucket (must exist before the state bucket) ──────────────────

resource "aws_s3_bucket" "state_access_logs" {
  bucket = "hello-world-terraform-state-logs-472303294041-2026"

  lifecycle {
    prevent_destroy = true
  }

  tags = {
    Name      = "Terraform State Access Logs"
    ManagedBy = "terraform-bootstrap"
  }
}

resource "aws_s3_bucket_ownership_controls" "state_access_logs" {
  bucket = aws_s3_bucket.state_access_logs.id

  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_public_access_block" "state_access_logs" {
  bucket = aws_s3_bucket.state_access_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ACL required for S3 log delivery when ownership is BucketOwnerPreferred.
resource "aws_s3_bucket_acl" "state_access_logs" {
  bucket = aws_s3_bucket.state_access_logs.id
  acl    = "log-delivery-write"

  depends_on = [
    aws_s3_bucket_ownership_controls.state_access_logs,
    aws_s3_bucket_public_access_block.state_access_logs,
  ]
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state_access_logs" {
  bucket = aws_s3_bucket.state_access_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_policy" "state_access_logs" {
  bucket = aws_s3_bucket.state_access_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyNonTLS"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.state_access_logs.arn,
          "${aws_s3_bucket.state_access_logs.arn}/*",
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.state_access_logs]
}

# ─── State bucket ─────────────────────────────────────────────────────────────

resource "aws_s3_bucket" "terraform_state" {
  bucket = "hello-world-terraform-state-472303294041-2026"

  lifecycle {
    prevent_destroy = true
  }

  tags = {
    Name      = "Terraform State"
    ManagedBy = "terraform-bootstrap"
  }
}

resource "aws_s3_bucket_ownership_controls" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.terraform_state.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_logging" "terraform_state" {
  bucket        = aws_s3_bucket.terraform_state.id
  target_bucket = aws_s3_bucket.state_access_logs.id
  target_prefix = "state-access-logs/"
}

# Expire non-current state versions after 90 days to control storage costs.
resource "aws_s3_bucket_lifecycle_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    id     = "expire-old-versions"
    status = "Enabled"

    noncurrent_version_expiration {
      noncurrent_days = 90
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  depends_on = [aws_s3_bucket_versioning.terraform_state]
}

# Enforce TLS-only access to state objects.
resource "aws_s3_bucket_policy" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyNonTLS"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.terraform_state.arn,
          "${aws_s3_bucket.terraform_state.arn}/*",
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.terraform_state]
}

# ─── DynamoDB lock table ───────────────────────────────────────────────────────

resource "aws_dynamodb_table" "terraform_lock" {
  name         = "terraform-state-lock"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled = true
  }

  lifecycle {
    prevent_destroy = true
  }

  tags = {
    Name      = "Terraform State Lock"
    ManagedBy = "terraform-bootstrap"
  }
}

# ─── Outputs ──────────────────────────────────────────────────────────────────

output "state_bucket_name" {
  value       = aws_s3_bucket.terraform_state.bucket
  description = "S3 bucket for Terraform remote state"
}

output "state_bucket_arn" {
  value       = aws_s3_bucket.terraform_state.arn
  description = "ARN of the state bucket — use in IAM policies"
}

output "lock_table_name" {
  value       = aws_dynamodb_table.terraform_lock.name
  description = "DynamoDB table for state locking"
}

output "lock_table_arn" {
  value       = aws_dynamodb_table.terraform_lock.arn
  description = "ARN of the lock table — use in IAM policies"
}
