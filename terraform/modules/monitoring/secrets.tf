# Terraform owns both secrets' full lifecycle, same pattern as the Redis
# module's AUTH token and the Cloudflare Tunnel's connector token (ADR-008)
# - the value itself still originates outside Terraform's world (a Slack
# incoming webhook, a Grafana Cloud API key - both human dashboard
# actions), but unlike a value Terraform could plausibly generate itself,
# these just need to *reach* Terraform once. That happens via a
# TF_VAR_-prefixed env var in CI (GitHub Actions secrets SLACK_WEBHOOK_URL
# / GRAFANA_CLOUD_API_KEY), never a value typed into terraform.tfvars
# (which is committed to git) and never a manual `aws secretsmanager
# create-secret` step to skip.
resource "aws_secretsmanager_secret" "slack_webhook" {
  name                    = "${var.project_name}-${var.environment}-slack-webhook-url"
  recovery_window_in_days = 0
  tags                    = var.tags
}

resource "aws_secretsmanager_secret_version" "slack_webhook" {
  secret_id     = aws_secretsmanager_secret.slack_webhook.id
  secret_string = var.slack_webhook_url
}

resource "aws_secretsmanager_secret" "grafana_cloud_api_key" {
  name                    = "${var.project_name}-${var.environment}-grafana-cloud-api-key"
  recovery_window_in_days = 0
  tags                    = var.tags
}

resource "aws_secretsmanager_secret_version" "grafana_cloud_api_key" {
  secret_id     = aws_secretsmanager_secret.grafana_cloud_api_key.id
  secret_string = var.grafana_cloud_api_key
}
