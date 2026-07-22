resource "aws_iam_role" "flower" {
  name               = "${var.project_name}-${var.environment}-flower-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "flower_ssm" {
  role       = aws_iam_role.flower.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

data "aws_iam_policy_document" "flower_secrets" {
  statement {
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [var.redis_auth_token_secret_arn]
  }
}

resource "aws_iam_role_policy" "flower_secrets" {
  name   = "${var.project_name}-${var.environment}-flower-secrets-read"
  role   = aws_iam_role.flower.id
  policy = data.aws_iam_policy_document.flower_secrets.json
}

resource "aws_iam_instance_profile" "flower" {
  name = "${var.project_name}-${var.environment}-flower-profile"
  role = aws_iam_role.flower.name
}

resource "aws_instance" "flower" {
  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = var.flower_instance_type
  subnet_id              = var.ops_subnet_id
  vpc_security_group_ids = [var.ops_security_group_id]
  iam_instance_profile   = aws_iam_instance_profile.flower.name

  associate_public_ip_address = false

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
    encrypted   = true
  }

  user_data = templatefile("${path.module}/templates/flower_user_data.sh.tpl", {
    redis_auth_token_secret_arn = var.redis_auth_token_secret_arn
    redis_host                  = var.redis_primary_endpoint_address
    redis_port                  = var.redis_port
    flower_port                 = var.flower_port
    aws_region                  = data.aws_region.current.name
  })

  user_data_replace_on_change = true

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-flower"
  })
}
