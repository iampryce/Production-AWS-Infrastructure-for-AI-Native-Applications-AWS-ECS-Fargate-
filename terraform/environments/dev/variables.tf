variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "project_name" {
  type    = string
  default = "aws-ai-native-infra"
}

variable "nat_type" {
  description = "\"fck-nat\" or \"nat-gateway\". No default — must come from this environment's terraform.tfvars."
  type        = string
}

variable "fck_nat_ha" {
  description = "Only applies when nat_type = \"fck-nat\". See terraform.tfvars for this environment's value."
  type        = bool
  default     = false
}

variable "multi_az" {
  description = "No default — must come from this environment's terraform.tfvars. false in dev/staging, true in prod."
  type        = bool
}

variable "automatic_failover_enabled" {
  description = "No default — must come from this environment's terraform.tfvars. false in dev/staging (single Redis node), true in prod (primary + replica, automatic failover)."
  type        = bool
}

variable "domain_name" {
  description = "Apex domain for Phase 6 (Route 53 + ACM + CloudFront)."
  type        = string
}

variable "cloudflare_account_id" {
  description = "Phase 7. Cloudflare account ID that owns the ops tunnel - not a secret, see terraform/modules/cloudflare-tunnel/variables.tf for where to find it."
  type        = string
}

# No default, sensitive, and deliberately absent from terraform.tfvars -
# supplied only via the TF_VAR_slack_webhook_url env var in
# terraform-dev.yml (GitHub Actions secret SLACK_WEBHOOK_URL).
variable "slack_webhook_url" {
  type      = string
  sensitive = true
}

variable "grafana_cloud_otlp_endpoint" {
  description = "Phase 9. Grafana Cloud OTLP gateway endpoint - not a secret."
  type        = string
}

variable "grafana_cloud_instance_id" {
  description = "Phase 9. Grafana Cloud stack/instance ID - not a secret."
  type        = string
}

# Same as slack_webhook_url - via TF_VAR_grafana_cloud_api_key
# (GitHub Actions secret GRAFANA_CLOUD_API_KEY), never tfvars.
variable "grafana_cloud_api_key" {
  type      = string
  sensitive = true
}
