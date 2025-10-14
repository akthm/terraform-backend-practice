variable "project"       { type = string }
variable "region"        { type = string }
variable "state_bucket"  { type = string }
variable "lock_table"    { type = string }
variable "deploy_bucket" { type = string }
variable "IsDevMode"     { type = bool }
variable "aws_profile" { type = string, default = null }

