variable "aws_region" {
  type        = string
  description = "AWS region for the provider (not the backend)."
  default     = "ap-south-1"
}

variable "environment" {
  type        = string
  description = "Env tag (dev/stage/prod)"
  default     = "dev"
}

variable "ssm_parameter_name" {
  type        = string
  description = "Name of the SSM parameter to create"
  default     = "/hello/runner"
}

variable "tags" {
  type        = map(string)
  description = "Extra tags merged into resources"
  default = {
    ManagedBy = "Terraform"
    Project   = "tf-hello-runner"
  }
}
