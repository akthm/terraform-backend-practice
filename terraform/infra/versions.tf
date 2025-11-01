terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Backend is configured at init-time via backend.hcl (not hard-coded here)
  backend "s3" {}
}
