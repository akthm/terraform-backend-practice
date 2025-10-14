terraform {
  required_version = ">= 1.6.0"

  backend "s3" {
    bucket         = "org-terraform-state-prod-123456789012"
    key            = "global/${terraform.workspace}/terraform.tfstate"
    region         = "ap-south-1"
    dynamodb_table = "org-terraform-locks"
    encrypt        = true
    kms_key_id     = "alias/tf-state"
  }
}
