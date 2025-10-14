terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.50" }
  }
}

provider "aws" {
  region = var.region
    profile = var.aws_profile

}

locals {
  tags = {
    Project = var.project
    Env     = "bootstrap"
    ManagedBy = "terraform"
  }
}

# State bucket
resource "aws_s3_bucket" "tf_state" {
  bucket = var.state_bucket
  force_destroy = var.IsDevMode ? true : false
  tags   = local.tags
}

resource "aws_s3_bucket_versioning" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id
  rule { 
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
    }
}

resource "aws_s3_bucket_public_access_block" "tf_state" {
  bucket                  = aws_s3_bucket.tf_state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# DynamoDB lock table
resource "aws_dynamodb_table" "tf_lock" {
  name         = var.lock_table
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"
  attribute {
      name = "LockID"
      type = "S" 
     }
  tags = local.tags
}

# Deploy artifacts bucket
resource "aws_s3_bucket" "deploy" {
  bucket = var.deploy_bucket
  force_destroy = var.IsDevMode ? true : false
  tags   = local.tags
}

resource "aws_s3_bucket_server_side_encryption_configuration" "deploy" {
  bucket = aws_s3_bucket.deploy.id
  rule { 
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" } 
  }
}

resource "aws_s3_bucket_public_access_block" "deploy" {
  bucket                  = aws_s3_bucket.deploy.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

