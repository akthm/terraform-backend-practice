terraform {
  required_version = ">= 1.6.0"

  backend "s3" {
    bucket         = "akthmbucketdevterraform"
    key            = "global/${terraform.workspace}/terraform.tfstate"
    region         = "ap-south-1"
    dynamodb_table = "akthm-lock-table-dev"
    encrypt        = true
    kms_key_id     = "alias/tf-state"
  }
}
