

# Useful identity/region data—great for tags and outputs
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# A super-safe resource to create in any account
resource "aws_ssm_parameter" "hello" {
  name        = var.ssm_parameter_name # e.g., "/hello/runner"
  description = "Hello from the EC2 GH Actions runner"
  type        = "String"
  value       = "deployed-by-github-actions"
  tags = merge(var.tags, {
    "Component" : "hello-ssm"
  })
}

# Another safe resource
resource "aws_cloudwatch_log_group" "hello" {
  name              = "/hello/runner"
  retention_in_days = 7
  tags = merge(var.tags, {
    "Component" : "hello-log"
  })
}

# Example of using tags everywhere
locals {
  base_tags = merge({
    Environment = var.environment
    DeployedBy  = "github-actions"
    # AccountId   = data.aws_caller_identity.current.account_id
    # Region      = data.aws_region.current.name
  }, var.tags)
}

# Apply base tags to both resources via default_tags
provider "aws" {
  region = var.aws_region
  default_tags {
    tags = local.base_tags
  }
}
