variable "project"       { type = string }
variable "region"        { type = string }
variable "state_bucket"  { type = string }
variable "lock_table"    { type = string }
variable "deploy_bucket" { type = string }
variable "IsDevMode"     { type = bool }
variable "aws_profile" {
     type = string 
     default = null
    }



# variable "allow_ssh_cidr"    { type = string  default = "" } # optional
variable "github_owner"      { 
    type = string 
    sensitive = true 
    }             
variable "github_repo"       { 
    type = string 
    sensitive = true
    }               # repo name (or leave empty if org-level)
variable "runner_labels"     { 
    type = list(string) 
    default = ["self-hosted","terraform-runner"] 
    }
variable "ssm_github_pat_name" { 
    type = string 
    sensitive = true
    }  # SSM Parameter Store name for GitHub PAT
# variable "ec2_key_name"      { 
#     type = string  
#     default = null 
#     } # optional if you want SSH

variable "instance_type"     { 
    type = string  
    default = "t2.micro" 
    }

variable "ec2_name"          { 
    type = string  
    default = "gha-terraform-runner" 
    }

variable "cw_log_group"      { 
    type = string   
    }

variable "state_key_prefix" {
  description = "Prefix inside the state bucket to allow (use * for all, or e.g., terraform/infra/)"
  type        = string
}