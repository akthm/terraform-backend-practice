IsDevMode=true
region="ap-south-1"
state_bucket="akthmbucketdevterraform"
lock_table="akthm-lock-table-dev"
deploy_bucket="akthm-deploy-bucket-dev"
project="akthm-terraform"
aws_profile="tf-admin"

github_owner="akthm"
github_repo="terraform-backend-practice"
ssm_github_pat_name="ppat"
# vpc_id="vpc-0bb1c2d3e4f5ghijk"
# subnet_id="subnet-0a1b2c3d4e5f6g7h8"
#ec2_key_name="akthm-ec2-keypair"
instance_type="t3.micro"
ec2_name="gha-terraform-runner-dev"
runner_labels=["self-hosted","terraform-runner","dev", "terraform-runner-dev"]
cw_log_group="/gha/runner"
