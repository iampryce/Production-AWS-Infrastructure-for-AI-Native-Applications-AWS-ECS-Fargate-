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

  # No key pair, no public IP - matches the rest of the ops subnet's
  # no-SSH-from-the-internet stance. SSM Session Manager covers direct
  # troubleshooting; cloudflared's outbound connection is what replaces the
  # bastion for reaching everything else back here.
  associate_public_ip_address = false

  user_data = templatefile("${path.module}/templates/user_data.sh.tpl", {
    tunnel_token_secret_arn = aws_secretsmanager_secret.tunnel_token.arn
    aws_region              = data.aws_region.current.name
  })

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-cloudflare-tunnel"
  })
}
