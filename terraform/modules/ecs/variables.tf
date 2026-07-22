variable "project_name" {
  type    = string
  default = "aws-ai-native-infra"
}

variable "environment" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "public_subnet_ids" {
  description = "For the ALB. values(module.network.public_subnet_ids)."
  type        = list(string)
}

variable "app_subnet_ids" {
  description = "For the ECS services. values(module.network.app_subnet_ids)."
  type        = list(string)
}

variable "alb_security_group_id" {
  type = string
}

variable "app_security_group_id" {
  type = string
}

variable "app_port" {
  description = "Must match the network module's app_port (the App SG's ALB->App ingress rule is already scoped to this port)."
  type        = number
  default     = 8000
}

# --- Placeholder images ---
#
# No real application image exists yet (Phases 10/11 build the FastAPI and
# Celery code). Terraform must never own or diff a real image *tag* per the
# decoupled-deploy rule, but a task definition still needs *some* pullable
# image to prove the ECS shape (cluster, task defs, services, autoscaling)
# actually works end to end rather than just planning cleanly.
# `python:3.12-slim` + a command override stands in: http.server on the app
# port for FastAPI (passes a real ALB health check), `sleep infinity` for
# Celery (stays alive, does nothing).
#
# `use_placeholder_images` is the one deliberate switch between the two
# states - flipping it to false points both task definitions at this
# module's own ECR repos on the `:prod` tag instead (computed from
# aws_ecr_repository.*.repository_url below, not passed in from outside,
# so there's no circular reference to the repos this same module creates).
# That flip happens once, by hand, after Phase 5's image-build-deploy
# pipeline has actually pushed something real to `:prod` - not before,
# since the ECS service would fail to pull a tag that doesn't exist yet.
variable "use_placeholder_images" {
  type    = bool
  default = true
}

variable "fastapi_placeholder_image" {
  type    = string
  default = "python:3.12-slim"
}

variable "celery_placeholder_image" {
  type    = string
  default = "python:3.12-slim"
}

variable "fastapi_cpu" {
  type    = number
  default = 256
}

variable "fastapi_memory" {
  type    = number
  default = 512
}

variable "celery_cpu" {
  type    = number
  default = 256
}

variable "celery_memory" {
  type    = number
  default = 512
}

variable "fastapi_desired_count" {
  type    = number
  default = 1
}

variable "celery_desired_count" {
  type    = number
  default = 1
}

variable "fastapi_autoscaling_max_capacity" {
  type    = number
  default = 3
}

variable "celery_autoscaling_max_capacity" {
  type    = number
  default = 3
}

variable "log_retention_days" {
  type    = number
  default = 7
}

# Secrets, wired into both task definitions as ECS "secrets" (Secrets
# Manager references resolved at container start), never as plain env vars.
variable "rds_master_user_secret_arn" {
  type = string
}

variable "rds_host" {
  type = string
}

variable "rds_db_name" {
  type = string
}

variable "rds_master_username" {
  type = string
}

variable "redis_auth_token_secret_arn" {
  type = string
}

variable "redis_primary_endpoint_address" {
  type = string
}

variable "redis_port" {
  type = number
}

# --- Phase 11: Celery worker's AI provider call + S3 result storage ---

# Not derived from module.cloudfront's output - that module already
# depends on this one's alb_dns_name, and referencing cloudfront's bucket
# name back here would create a module dependency cycle. The bucket name
# is fully deterministic ("${project_name}-${environment}-assets", no
# random suffix - see cloudfront/s3.tf), so the root module just
# constructs the same string directly instead.
variable "assets_bucket_name" {
  type = string
}

variable "assets_bucket_arn" {
  type = string
}

# CloudFront routes /assets/* straight to the S3 origin with no
# origin_path rewrite, so an object stored at key "assets/generations/
# <id>.json" is reachable at "<public_asset_base_url>/generations/<id>.json".
variable "public_asset_base_url" {
  description = "e.g. https://rivetrecords.online/assets - not a secret, just where results become publicly viewable."
  type        = string
}

# No default - supplied via TF_VAR_openai_api_key (GitHub Actions secret
# OPENAI_API_KEY), never terraform.tfvars. Same pattern as the monitoring
# module's slack_webhook_url/grafana_cloud_api_key (ADR-010).
variable "openai_api_key" {
  type      = string
  sensitive = true
}

variable "tags" {
  type    = map(string)
  default = {}
}
