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

  # user_data only ever executes at first boot - without this, changing the
  # boot script (as this fix does) would update Terraform's state but never
  # actually re-run on the already-running instance. Matches the intent
  # already stated in the boot script's own comment: a broken or
  # out-of-date boot means replace the instance, not patch it in place.
  user_data_replace_on_change = true

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-cloudflare-tunnel"
  })
}
