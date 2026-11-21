# ------------------------------------------------------------------------------
# Compute Module: Zero-SSH, Auto-Healing Worker Node
# ------------------------------------------------------------------------------

# Fetch Latest Amazon Linux 2023 AMI
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# ------------------------------------------------------------------------------
# IAM Role and Instance Profile (Zero-SSH via SSM Session Manager)
# ------------------------------------------------------------------------------
resource "aws_iam_role" "worker" {
  name_prefix = "${var.project_name}-${var.environment}-role-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name        = "${var.project_name}-worker-role"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# Attach AWS Systems Manager (SSM) Managed Instance Core Policy
# Allows browser-based CLI access without Port 22 SSH or keypairs
resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.worker.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# S3 Access Policy: Strict least-privilege permissions
resource "aws_iam_policy" "s3_access" {
  name_prefix = "${var.project_name}-${var.environment}-s3-policy-"
  description = "Allows EC2 worker node to read/delete from raw bucket and write to processed bucket"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ListS3Buckets"
        Effect = "Allow"
        Action = [
          "s3:ListBucket"
        ]
        Resource = [
          var.raw_bucket_arn,
          var.processed_bucket_arn
        ]
      },
      {
        Sid    = "RawBucketIngestionAndPurge"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:DeleteObject"
        ]
        Resource = "${var.raw_bucket_arn}/*"
      },
      {
        Sid    = "ProcessedBucketDelivery"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:PutObjectAcl"
        ]
        Resource = "${var.processed_bucket_arn}/*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "s3_access_attach" {
  role       = aws_iam_role.worker.name
  policy_arn = aws_iam_policy.s3_access.arn
}

resource "aws_iam_instance_profile" "worker" {
  name_prefix = "${var.project_name}-${var.environment}-profile-"
  role        = aws_iam_role.worker.name
}

# ------------------------------------------------------------------------------
# Security Group: ZERO-SSH (0 Inbound Rules)
# ------------------------------------------------------------------------------
resource "aws_security_group" "worker" {
  name_prefix = "${var.project_name}-${var.environment}-sg-"
  description = "Strict security group: 0 inbound rules (Zero SSH), egress for internal VPC endpoints"
  vpc_id      = var.vpc_id

  # ZERO Inbound Rules!
  # Port 22 SSH is completely blocked for security hardening.
  # Management is handled solely through AWS Systems Manager Session Manager.

  egress {
    description = "Allow all outbound traffic (S3 Gateway Endpoint and AWS internal API routing)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.project_name}-${var.environment}-worker-sg"
    Environment = var.environment
    ManagedBy   = "Terraform"
    Security    = "Zero-SSH"
  }
}

# ------------------------------------------------------------------------------
# Launch Template (t2.micro / t3.micro Free Tier)
# ------------------------------------------------------------------------------
resource "aws_launch_template" "worker" {
  name_prefix   = "${var.project_name}-${var.environment}-lt-"
  image_id      = data.aws_ami.al2023.id
  instance_type = var.instance_type

  iam_instance_profile {
    arn = aws_iam_instance_profile.worker.arn
  }

  vpc_security_group_ids = [aws_security_group.worker.id]

  # Root EBS Volume: 8 GB gp3 (Free Tier covers up to 30 GB total)
  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size           = 8
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  # Enforce IMDSv2 (Enterprise Security Standard)
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  user_data = base64encode(<<EOF
#!/bin/bash
exec > >(tee /var/log/user-data.log | logger -t user-data -s 2>/dev/console) 2>&1
echo "=== [BOOT] Initializing Enterprise Private Worker Node ==="

# Optional packages (will succeed or skip gracefully)
dnf install -y python3-pip python3-boto3 python3-pillow || true

mkdir -p /opt/worker
cat <<'PY_SCRIPT' > /opt/worker/processor.py
${file("${path.module}/../../worker_app/processor.py")}
PY_SCRIPT
chmod +x /opt/worker/processor.py

cat <<ENV_EOF > /etc/worker.env
RAW_BUCKET=${var.raw_bucket_name}
PROCESSED_BUCKET=${var.processed_bucket_name}
POLL_INTERVAL=5
ENV_EOF

cat <<'SERVICE_EOF' > /etc/systemd/system/image-processor.service
[Unit]
Description=Automated Private Image/Document Processor
After=network.target

[Service]
Type=simple
User=root
EnvironmentFile=/etc/worker.env
ExecStart=/usr/bin/python3 /opt/worker/processor.py
Restart=always
RestartSec=5
StandardOutput=journal+console
StandardError=journal+console

[Install]
WantedBy=multi-user.target
SERVICE_EOF

systemctl daemon-reload
systemctl enable image-processor.service
systemctl start image-processor.service
echo "=== [BOOT] Worker Node Online & Systemd Service Started ==="
EOF
  )

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name        = "${var.project_name}-${var.environment}-worker-node"
      Environment = var.environment
      ManagedBy   = "Terraform"
      Tier        = "FreeTier"
    }
  }

  tags = {
    Name        = "${var.project_name}-${var.environment}-launch-template"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# ------------------------------------------------------------------------------
# Auto Scaling Group (Auto-Healing: min=1, max=1, desired=1)
# ------------------------------------------------------------------------------
resource "aws_autoscaling_group" "worker" {
  name_prefix         = "${var.project_name}-${var.environment}-asg-"
  vpc_zone_identifier = [var.private_subnet_id]

  min_size         = 1
  max_size         = 1
  desired_capacity = 1

  health_check_type         = "EC2"
  health_check_grace_period = 300

  launch_template {
    id      = aws_launch_template.worker.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "${var.project_name}-${var.environment}-private-worker"
    propagate_at_launch = true
  }

  tag {
    key                 = "Environment"
    value               = var.environment
    propagate_at_launch = true
  }

  lifecycle {
    create_before_destroy = true
  }
}
