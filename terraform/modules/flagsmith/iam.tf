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
  name               = "${var.project_name}-${var.environment}-flagsmith-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json

  tags = var.tags
}

# SSM Session Manager for troubleshooting this instance directly - same
# no-public-bastion reasoning used everywhere else in this project (the
# fck-nat instances, the Cloudflare Tunnel instance).
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.this.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Scoped to exactly the two secrets this instance's boot script reads -
# the RDS-managed master password and the Django secret key - not a
# broader Secrets Manager grant.
data "aws_iam_policy_document" "flagsmith_secrets" {
  statement {
    actions = ["secretsmanager:GetSecretValue"]
    resources = [
      aws_db_instance.flagsmith.master_user_secret[0].secret_arn,
      aws_secretsmanager_secret.django_secret_key.arn,
    ]
  }
}

resource "aws_iam_role_policy" "flagsmith_secrets" {
  name   = "${var.project_name}-${var.environment}-flagsmith-secrets-read"
  role   = aws_iam_role.this.id
  policy = data.aws_iam_policy_document.flagsmith_secrets.json
}

resource "aws_iam_instance_profile" "this" {
  name = "${var.project_name}-${var.environment}-flagsmith-profile"
  role = aws_iam_role.this.name
}
