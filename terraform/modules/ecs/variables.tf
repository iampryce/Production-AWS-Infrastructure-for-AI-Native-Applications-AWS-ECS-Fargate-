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
# Celery code; Phase 5 builds the push pipeline). Terraform must never own
# or diff a real image tag per the decoupled-deploy rule, but a task
# definition still needs *some* pullable image to prove the ECS shape
# (cluster, task defs, services, autoscaling) actually works end to end
# rather than just planning cleanly. `python:3.12-slim` + a command
# override stands in: http.server on the app port for FastAPI (passes a
# real ALB health check), `sleep infinity` for Celery (stays alive, does
# nothing). Swapping to the real image later means changing these two
# variables to `"${ecr_repository_url}:prod"` and dropping the command
# override - a deliberate one-time Terraform change, not a per-deploy one.
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

variable "tags" {
  type    = map(string)
  default = {}
}
