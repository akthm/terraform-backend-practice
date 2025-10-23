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
}

# Attach SSM core so you can manage without SSH
resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.runner_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# (Optional) CloudWatch agent for logs (attach if you push logs)
# resource "aws_iam_role_policy_attachment" "cw_agent" {
#   role       = aws_iam_role.runner_role.name
#   policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
# }

# Least-priv for reading the GitHub PAT from SSM Parameter Store (SecureString)
data "aws_iam_policy_document" "ssm_read_pat" {
  statement {
    actions   = ["ssm:GetParameter", "ssm:GetParameters", "kms:Decrypt"]
    resources = [
      "arn:aws:ssm:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:parameter${var.ssm_github_pat_name}",
      # if the parameter is KMS-encrypted with a CMK, grant kms:Decrypt for that CMK
      "*"
    ]
  }
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
  vpc_id      = var.vpc_id

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


data "template_cloudinit_config" "runner_userdata" {
  gzip          = true
  base64_encode = true

  part {
    filename     = "cloud-config.txt"
    content_type = "text/cloud-config"
    content = <<-CLOUDCFG
      #cloud-config
      package_update: true
      package_upgrade: true
      packages:
        - git
        - unzip
        - jq
        - curl
        - apt-transport-https
        - ca-certificates
        - gnupg
      runcmd:
        - [ bash, -lc, "/usr/local/bin/runner-bootstrap.sh" ]
    CLOUDCFG
  }

  part {
    filename     = "runner-bootstrap.sh"
    content_type = "text/x-shellscript"
    content = <<-BOOTSTRAP
      #!/usr/bin/env bash
      set -Eeuo pipefail

      GH_OWNER="${var.github_owner}"
      GH_REPO="${var.github_repo}"          # empty means org-level
      REPO_OR_ORG_PATH="${local.repo_or_org_path}"
      LABELS="${local.runner_labels_csv}"
      SSM_GH_PAT_PARAM="${var.ssm_github_pat_name}"

      LOG_DIR="/var/log/gha"
      RUNNER_DIR="/opt/actions-runner"
      UNIT_NAME="gha-runner.service"

      mkdir -p "$LOG_DIR"
      exec > >(tee -a "$LOG_DIR/bootstrap.log") 2>&1

      echo "[*] Installing AWS CLI v2 (if missing)…"
      if ! command -v aws >/dev/null 2>&1; then
        tmpd=$(mktemp -d)
        pushd "$tmpd"
        curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o awscliv2.zip
        unzip -q awscliv2.zip
        ./aws/install
        popd
        rm -rf "$tmpd"
      fi

      echo "[*] Install Docker (used by many workflows)…"
      if ! command -v docker >/dev/null 2>&1; then
        install -m 0755 -d /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        chmod a+r /etc/apt/keyrings/docker.gpg
        echo \
          "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
          $(. /etc/os-release && echo $VERSION_CODENAME) stable" \
          | tee /etc/apt/sources.list.d/docker.list > /dev/null
        apt-get update -y
        apt-get install -y docker-ce docker-ce-cli containerd.io
        usermod -aG docker ubuntu || true
        systemctl enable --now docker
      fi

      echo "[*] Fetching GitHub PAT from SSM…"
      GH_PAT=$(aws ssm get-parameter --name "$SSM_GH_PAT_PARAM" --with-decryption --query 'Parameter.Value' --output text)

      echo "[*] Getting registration token from GitHub API…"
      REG_TOKEN=$(curl -fsSL -X POST \
        -H "Authorization: token $${GH_PAT}" \
        -H "Accept: application/vnd.github+json" \
        "https://api.github.com/$${REPO_OR_ORG_PATH}/actions/runners/registration-token" \
        | jq -r .token)

      echo "[*] Install latest GitHub Actions runner…"
      mkdir -p "$RUNNER_DIR"
      cd "$RUNNER_DIR"
      # get latest release tag
      RUNNER_VERSION=$(curl -fsSL https://api.github.com/repos/actions/runner/releases/latest | jq -r .tag_name | sed 's/^v//')
      curl -fsSL -o actions-runner-linux-x64-$${RUNNER_VERSION}.tar.gz \
        https://github.com/actions/runner/releases/download/v$${RUNNER_VERSION}/actions-runner-linux-x64-$${RUNNER_VERSION}.tar.gz
      tar xzf actions-runner-linux-x64-$${RUNNER_VERSION}.tar.gz
      chown -R ubuntu:ubuntu "$RUNNER_DIR"

      echo "[*] Create systemd unit…"
      cat >/etc/systemd/system/$${UNIT_NAME} <<'UNIT'
      [Unit]
      Description=GitHub Actions Runner (ephemeral)
      After=network-online.target
      Wants=network-online.target

      [Service]
      Type=simple
      WorkingDirectory=/opt/actions-runner
      Environment="GH_OWNER=$${GH_OWNER}"
      Environment="GH_REPO=$${GH_REPO}"
      Environment="REPO_OR_ORG_PATH=$${REPO_OR_ORG_PATH}"
      Environment="SSM_GH_PAT_PARAM=$${SSM_GH_PAT_PARAM}"
      Environment="LABELS=$${LABELS}"
      ExecStart=/usr/local/bin/runner-loop.sh
      ExecStop=/usr/local/bin/runner-stop.sh
      Restart=always
      RestartSec=5

      [Install]
      WantedBy=multi-user.target
      UNIT

      echo "[*] Create runner loop script (ephemeral, auto re-register)…"
      cat >/usr/local/bin/runner-loop.sh <<'LOOP'
      #!/usr/bin/env bash
      set -Eeuo pipefail

      LOG_DIR="/var/log/gha"
      RUNNER_DIR="/opt/actions-runner"

      while true; do
        echo "[*] Refresh GH PAT + registration token…"
        GH_PAT=$(aws ssm get-parameter --name "$${SSM_GH_PAT_PARAM}" --with-decryption --query 'Parameter.Value' --output text)
        REG_TOKEN=$(curl -fsSL -X POST \
          -H "Authorization: token $${GH_PAT}" \
          -H "Accept: application/vnd.github+json" \
          "https://api.github.com/$${REPO_OR_ORG_PATH}/actions/runners/registration-token" \
          | jq -r .token)

        cd "$RUNNER_DIR"
        # remove old config if exists (ephemeral run cleans up, but be safe)
        ./config.sh remove --token "$${REG_TOKEN}" >/dev/null 2>&1 || true

        if [[ -n "$${GH_REPO}" ]]; then
          URL="https://github.com/$${GH_OWNER}/$${GH_REPO}"
        else
          URL="https://github.com/$${GH_OWNER}"
        fi

        ./config.sh \
          --url "$${URL}" \
          --token "$${REG_TOKEN}" \
          --name "$(hostname)-$(date +%s)" \
          --labels "$${LABELS}" \
          --unattended \
          --ephemeral

        echo "[*] Starting runner once (ephemeral)…"
        ./run.sh >> "$${LOG_DIR}/runner.log" 2>&1 || true

        echo "[*] Runner finished a job or crashed; reconfiguring in 5s…"
        sleep 5
      done
      LOOP
      chmod +x /usr/local/bin/runner-loop.sh

      echo "[*] Create stop script to deregister on shutdown…"
      cat >/usr/local/bin/runner-stop.sh <<'STOP'
      #!/usr/bin/env bash
      set -Eeuo pipefail
      RUNNER_DIR="/opt/actions-runner"
      # Best-effort deregister
      if [[ -x "$${RUNNER_DIR}/config.sh" ]]; then
        GH_PAT=$(aws ssm get-parameter --name "$${SSM_GH_PAT_PARAM}" --with-decryption --query 'Parameter.Value' --output text)
        REG_TOKEN=$(curl -fsSL -X POST \
          -H "Authorization: token $${GH_PAT}" \
          -H "Accept: application/vnd.github+json" \
          "https://api.github.com/$${REPO_OR_ORG_PATH}/actions/runners/registration-token" \
          | jq -r .token)
        "$${RUNNER_DIR}/config.sh" remove --unattended --token "$${REG_TOKEN}" || true
      fi
      STOP
      chmod +x /usr/local/bin/runner-stop.sh

      echo "[*] Enable & start runner service…"
      systemctl daemon-reload
      systemctl enable --now $${UNIT_NAME}
      echo "[*] Bootstrap complete."
    BOOTSTRAP
  }
}

resource "aws_instance" "gha_runner" {
  ami                         = data.aws_ami.ubuntu_22.id
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = [aws_security_group.runner_sg.id]
  iam_instance_profile        = aws_iam_instance_profile.runner_profile.name
  key_name                    = var.ec2_key_name # optional
  associate_public_ip_address = true

  user_data_base64 = data.template_cloudinit_config.runner_userdata.rendered

  tags = {
    Name = var.ec2_name
    Role = "github-actions-runner"
  }
}
