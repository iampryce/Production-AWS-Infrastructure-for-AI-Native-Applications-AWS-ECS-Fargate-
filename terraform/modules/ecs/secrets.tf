# Terraform owns this secret's lifecycle, same pattern as the monitoring
# module's Slack webhook/Grafana API key (ADR-010) - the OpenAI key
# itself is a human dashboard action with no Terraform provider path
# worth building, but getting the value into Terraform needs nothing
# beyond the TF_VAR_openai_api_key env var already wired in
# terraform-dev.yml.
resource "aws_secretsmanager_secret" "openai_api_key" {
  name                    = "${var.project_name}-${var.environment}-openai-api-key"
  recovery_window_in_days = 0
  tags                    = var.tags
}

resource "aws_secretsmanager_secret_version" "openai_api_key" {
  secret_id     = aws_secretsmanager_secret.openai_api_key.id
  secret_string = var.openai_api_key
}
