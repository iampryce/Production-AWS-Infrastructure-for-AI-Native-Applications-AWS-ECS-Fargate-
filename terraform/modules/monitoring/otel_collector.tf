data "aws_region" "current" {}

data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "otel_collector" {
  name               = "${var.project_name}-${var.environment}-otel-collector-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "otel_collector_ssm" {
  role       = aws_iam_role.otel_collector.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

data "aws_iam_policy_document" "otel_collector_secrets" {
  statement {
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_secretsmanager_secret.grafana_cloud_api_key.arn]
  }
}

resource "aws_iam_role_policy" "otel_collector_secrets" {
  name   = "${var.project_name}-${var.environment}-otel-collector-secrets-read"
  role   = aws_iam_role.otel_collector.id
  policy = data.aws_iam_policy_document.otel_collector_secrets.json
}

resource "aws_iam_instance_profile" "otel_collector" {
  name = "${var.project_name}-${var.environment}-otel-collector-profile"
  role = aws_iam_role.otel_collector.name
}

locals {
  otel_collector_config = templatefile("${path.module}/templates/otel-collector-config.yaml.tpl", {
    grafana_cloud_otlp_endpoint = var.grafana_cloud_otlp_endpoint
  })
}

resource "aws_instance" "otel_collector" {
  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = var.otel_instance_type
  subnet_id              = var.ops_subnet_id
  vpc_security_group_ids = [var.ops_security_group_id]
  iam_instance_profile   = aws_iam_instance_profile.otel_collector.name

  # No key pair, no public IP - same pattern as every other ops-subnet
  # instance in this project.
  associate_public_ip_address = false

  # Docker images for the collector + Jaeger together are large enough
  # that AL2023's default 8GB root disk isn't safe - hit exactly this on
  # the Flagsmith instance in Phase 8 (ADR-009). 30GB, same fix.
  root_block_device {
    volume_size = 30
    volume_type = "gp3"
    encrypted   = true
  }

  user_data = templatefile("${path.module}/templates/otel_user_data.sh.tpl", {
    grafana_cloud_api_key_secret_arn = aws_secretsmanager_secret.grafana_cloud_api_key.arn
    grafana_cloud_instance_id        = var.grafana_cloud_instance_id
    otel_collector_config            = local.otel_collector_config
    aws_region                       = data.aws_region.current.name
  })

  user_data_replace_on_change = true

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-otel-collector"
  })
}
