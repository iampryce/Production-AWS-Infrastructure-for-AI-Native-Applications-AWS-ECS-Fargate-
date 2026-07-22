data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "this" {
  name               = "${var.project_name}-${var.environment}-cloudflare-tunnel-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json

  tags = var.tags
}

# SSM Session Manager for troubleshooting the instance itself - same
# no-public-bastion reasoning used for the fck-nat instances. This is for
# reaching this one box directly; the tunnel is what replaces a bastion for
# reaching everything else in the ops subnet.
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.this.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

data "aws_iam_policy_document" "tunnel_token_secret" {
  statement {
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_secretsmanager_secret.tunnel_token.arn]
  }
}

resource "aws_iam_role_policy" "tunnel_token_secret" {
  name   = "${var.project_name}-${var.environment}-cloudflare-tunnel-token-read"
  role   = aws_iam_role.this.id
  policy = data.aws_iam_policy_document.tunnel_token_secret.json
}

resource "aws_iam_instance_profile" "this" {
  name = "${var.project_name}-${var.environment}-cloudflare-tunnel-profile"
  role = aws_iam_role.this.name
}
