data "aws_region" "current" {}

data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

resource "aws_instance" "this" {
  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = var.instance_type
  subnet_id              = var.ops_subnet_id
  vpc_security_group_ids = [var.ops_security_group_id]
  iam_instance_profile   = aws_iam_instance_profile.this.name

  # No key pair, no public IP - matches every other ops-subnet instance in
  # this project. SSM Session Manager covers direct troubleshooting; the
  # Cloudflare Tunnel (Phase 7) is what admin traffic to the Flagsmith UI
  # rides on, not a public route.
  associate_public_ip_address = false

  user_data = templatefile("${path.module}/templates/user_data.sh.tpl", {
    db_secret_arn                = aws_db_instance.flagsmith.master_user_secret[0].secret_arn
    django_secret_key_secret_arn = aws_secretsmanager_secret.django_secret_key.arn
    db_host                      = aws_db_instance.flagsmith.address
    db_port                      = aws_db_instance.flagsmith.port
    db_name                      = var.db_name
    db_username                  = var.db_master_username
    flagsmith_port               = var.flagsmith_port
    aws_region                   = data.aws_region.current.name
  })

  # Same reasoning as the Cloudflare Tunnel module: user_data only runs at
  # first boot, so a changed boot script must replace the instance to
  # actually take effect.
  user_data_replace_on_change = true

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-flagsmith"
  })
}
