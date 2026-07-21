provider "aws" {
  region = var.aws_region
}

# S3 bucket names are globally unique across all AWS accounts, not just
# this one — a random suffix avoids collisions without baking the account
# ID into the name.
resource "random_id" "state_bucket_suffix" {
  byte_length = 4
}

locals {
  state_bucket_name = "${var.project_name}-tfstate-${random_id.state_bucket_suffix.hex}"
}

resource "aws_s3_bucket" "terraform_state" {
  bucket = local.state_bucket_name

  lifecycle {
    prevent_destroy = true
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
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# No DynamoDB lock table — Terraform >= 1.10's native S3 locking
# (`use_lockfile = true` in each environment's backend block) uses
# conditional writes against this same bucket instead.
