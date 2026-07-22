variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "ops_subnet_id" {
  type = string
}

variable "ops_security_group_id" {
  type = string
}

# --- Infra-level pipeline: CloudWatch -> SNS -> Lambda -> Slack ---

variable "ecs_cluster_name" {
  type = string
}

variable "fastapi_service_name" {
  type = string
}

variable "celery_service_name" {
  type = string
}

variable "alb_arn_suffix" {
  type = string
}

variable "fastapi_target_group_arn_suffix" {
  type = string
}

variable "rds_db_instance_id" {
  type = string
}

variable "redis_replication_group_id" {
  type = string
}

# No default - must be supplied via the TF_VAR_slack_webhook_url env var
# (GitHub Actions secret SLACK_WEBHOOK_URL in terraform-dev.yml), never
# terraform.tfvars, which is committed to git. You create the webhook
# itself by hand (Slack -> a workspace -> Apps -> Incoming Webhooks) -
# that part's still a human dashboard action with no Terraform provider
# path worth building - but getting the resulting URL into Terraform
# needs nothing more than that one env var. sensitive = true keeps it out
# of plan/apply log output.
variable "slack_webhook_url" {
  type      = string
  sensitive = true
}

variable "ecs_cpu_alarm_threshold" {
  type    = number
  default = 80
}

variable "ecs_memory_alarm_threshold" {
  type    = number
  default = 80
}

variable "alb_5xx_alarm_threshold" {
  description = "Count of target 5xx responses in one evaluation period."
  type        = number
  default     = 10
}

variable "rds_cpu_alarm_threshold" {
  type    = number
  default = 80
}

variable "rds_free_storage_alarm_threshold_bytes" {
  description = "Default 2GB - dev's RDS allocated_storage default is 20GB (main rds module), so this trips well before actually running out."
  type        = number
  default     = 2000000000
}

variable "redis_cpu_alarm_threshold" {
  type    = number
  default = 80
}

# --- App-level pipeline: self-hosted OTel collector -> Grafana Cloud + Jaeger ---

# Not a secret - just an OTLP endpoint URL. Grafana Cloud's own API key is
# what authenticates against it, and that's the actual secret below.
variable "grafana_cloud_otlp_endpoint" {
  description = "Grafana Cloud OTLP gateway endpoint, e.g. https://otlp-gateway-<region>.grafana.net/otlp. From your Grafana Cloud stack's connection details."
  type        = string
}

# Not a secret - identifies which Grafana Cloud stack, not a credential.
variable "grafana_cloud_instance_id" {
  description = "Grafana Cloud stack/instance ID, from the same connection details page as the OTLP endpoint."
  type        = string
}

# Same reasoning as slack_webhook_url - supplied via TF_VAR_grafana_cloud_
# api_key (GitHub Actions secret GRAFANA_CLOUD_API_KEY), never tfvars. The
# boot script combines it with grafana_cloud_instance_id and
# base64-encodes the pair itself for the OTLP gateway's Basic auth header,
# rather than asking you to pre-encode anything by hand.
variable "grafana_cloud_api_key" {
  type      = string
  sensitive = true
}

variable "otel_instance_type" {
  description = "Runs both the OTel Collector and self-hosted Jaeger (all-in-one) as separate containers on one instance."
  type        = string
  default     = "t3.small"
}

# --- Flower: standalone, self-hosted, no external forwarding ---

variable "redis_primary_endpoint_address" {
  type = string
}

variable "redis_port" {
  type = number
}

variable "redis_auth_token_secret_arn" {
  type = string
}

variable "flower_instance_type" {
  type    = string
  default = "t3.micro"
}

variable "flower_port" {
  type    = number
  default = 5555
}

variable "tags" {
  type    = map(string)
  default = {}
}
