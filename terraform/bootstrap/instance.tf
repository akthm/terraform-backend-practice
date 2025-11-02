# variables you likely already have

locals {
  runner_labels_csv = join(",", var.runner_labels)
  # Set this to "" to register to an ORG instead of repo
  repo_or_org_path  = length(var.github_repo) > 0 ? "repos/${var.github_owner}/${var.github_repo}" : "orgs/${var.github_owner}"
}

data "aws_ami" "ubuntu_22" {
  owners      = ["099720109477"] # Canonical
  most_recent = true
  filter { 
    name = "name" 
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"] 
    }
}

# --- IAM role for the runner EC2 ---
resource "aws_iam_role" "runner_role" {
  name               = "${var.ec2_name}-role"
  assume_role_policy = data.aws_iam_policy_document.runner_ec2_trust.json
}

data "aws_iam_policy_document" "runner_ec2_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals { 
        type = "Service" 
        identifiers = ["ec2.amazonaws.com"] 
        }
  }

   

  # statement {
  #   sid     = "UseKmsForState"
  #   actions = ["kms:Encrypt","kms:Decrypt","kms:ReEncrypt*","kms:GenerateDataKey*","kms:DescribeKey"]
  #   resources = [aws_kms_key.tf_state.arn]
  # }

}

# Attach SSM core so you can manage without SSH
resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.runner_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

#  CloudWatch agent for logs (attach if you push logs)
resource "aws_iam_role_policy_attachment" "cw_agent" {
  role       = aws_iam_role.runner_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# Least-priv for reading the GitHub PAT from SSM Parameter Store (SecureString)
data "aws_iam_policy_document" "ssm_read_pat" {
  statement {
    actions   = ["ssm:GetParameter", "ssm:GetParameters", "ssm:PutParameter", "kms:Decrypt", "logs:TagResource", "ssm:AddTagsToResource", "logs:ListTagsForResource", "logs:DeleteLogGroup"]
    resources = [
      "*"
    ]
  }
   statement {
    sid     = "BackendState"
    actions = ["s3:GetObject","s3:PutObject","s3:DeleteObject","s3:ListBucket","s3:GetBucketLocation"]
    resources = [
      aws_s3_bucket.tf_state.arn,
      "${aws_s3_bucket.tf_state.arn}/${var.state_key_prefix}*"
    ]
  }

  # statement {
  #   sid     = "LockTable"
  #   actions = ["dynamodb:GetItem","dynamodb:PutItem","dynamodb:DeleteItem","dynamodb:DescribeTable","dynamodb:UpdateItem"]
  #   resources = [aws_dynamodb_table.tf_lock.arn]
  # }
}

resource "aws_iam_policy" "ssm_read_pat" {
  name        = "${var.ec2_name}-ssm-read-github-pat"
  description = "Allow reading GitHub PAT from SSM"
  policy      = data.aws_iam_policy_document.ssm_read_pat.json
}

resource "aws_iam_role_policy_attachment" "attach_ssm_read_pat" {
  role       = aws_iam_role.runner_role.name
  policy_arn = aws_iam_policy.ssm_read_pat.arn
}

# (Recommended) A least-priv policy to allow Terraform to act against your AWS infra.
# Replace with your exact needs (S3/DynamoDB state, VPC, EC2, IAM, etc.). Keep least-priv!
# resource "aws_iam_policy" "terraform_permissions" { ... }
# resource "aws_iam_role_policy_attachment" "attach_tf_perm" {
#   role       = aws_iam_role.runner_role.name
#   policy_arn = aws_iam_policy.terraform_permissions.arn
# }

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

resource "aws_iam_instance_profile" "runner_profile" {
  name = "${var.ec2_name}-profile"
  role = aws_iam_role.runner_role.name
}

# --- Security Group ---
resource "aws_security_group" "runner_sg" {
  name        = "${var.ec2_name}-sg"
  description = "Minimal SG for self-hosted GitHub Actions runner"
  vpc_id      = aws_vpc.main.id


  # SSM requires no inbound (it uses the agent outbound). Keep inbound closed.
#   dynamic "ingress" {
#     for_each = length(var.allow_ssh_cidr) > 0 ? [1] : []
#     content {
#       description = "SSH (optional)"
#       from_port   = 22
#       to_port     = 22
#       protocol    = "tcp"
#       cidr_blocks = [var.allow_ssh_cidr]
#     }
#   }

  egress {
    description = "All egress"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.ec2_name}-sg" }
}


# --- Render bootstrap with templatefile() ---
# 1) A small cloud-config to install packages and call the script
locals {
  cloud_config = <<-YAML
    #cloud-config
    package_update: true
    package_upgrade: true
    packages:
      - unzip
      - jq
      - curl
      - ca-certificates
      - gnupg
      - apt-transport-https
    runcmd:
      - [ bash, -lc, "/usr/local/bin/gha-bootstrap.sh" ]
  YAML
}

# 2) The actual shell script content, rendered with Terraform variables
locals {
  gha_bootstrap = templatefile("${path.module}/files/gha-bootstrap.sh.tftpl", {
    github_owner        = var.github_owner
    github_repo         = var.github_repo
    repo_or_org_path    = local.repo_or_org_path
    runner_labels_csv   = local.runner_labels_csv
    ssm_github_pat_name = var.ssm_github_pat_name
    cw_log_group        = var.cw_log_group
  })
}

# 3) Combine both parts into proper cloud-init MIME
data "template_cloudinit_config" "gha_bootstrap" {
  gzip          = true
  base64_encode = true

  part {
    content_type = "text/cloud-config"
    content      = local.cloud_config
  }

  part {
    filename     = "gha-bootstrap.sh"
    content_type = "text/x-shellscript"
    content      = local.gha_bootstrap
  }
}

resource "aws_instance" "gha_runner" {
  ami                         = data.aws_ami.ubuntu_22.id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public_1.id
  vpc_security_group_ids      = [aws_security_group.runner_sg.id]
  iam_instance_profile        = aws_iam_instance_profile.runner_profile.name
#   key_name                    = var.ec2_key_name # optional
  associate_public_ip_address = true

  user_data_base64 = data.template_cloudinit_config.gha_bootstrap.rendered

  tags = {
    Name = var.ec2_name
    Role = "github-actions-runner"
  }
}
