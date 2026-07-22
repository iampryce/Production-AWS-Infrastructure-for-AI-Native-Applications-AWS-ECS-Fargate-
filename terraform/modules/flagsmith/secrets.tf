# Flagsmith needs a stable Django secret key (session/token signing) - if
# left unset the container generates a random one on every start, which
# would invalidate sessions on every restart/replacement. Same
# random_password + Secrets Manager pattern as the Redis module's AUTH
# token, since - like that token - there's no AWS-managed lifecycle for
# this kind of value the way there is for the RDS master password above.
resource "random_password" "django_secret_key" {
  length  = 50
  special = true
}

resource "aws_secretsmanager_secret" "django_secret_key" {
  name = "${var.project_name}-${var.environment}-flagsmith-django-secret-key"

  # Same fast-rebuild reasoning as the Redis/Cloudflare Tunnel modules -
  # this project is built and torn down quickly, and this value has
  # nothing worth a 30-day recovery window.
  recovery_window_in_days = 0

  tags = var.tags
}

resource "aws_secretsmanager_secret_version" "django_secret_key" {
  secret_id     = aws_secretsmanager_secret.django_secret_key.id
  secret_string = random_password.django_secret_key.result
}
