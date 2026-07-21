variable "project_name" {
  type    = string
  default = "aws-ai-native-infra"
}

variable "environment" {
  type = string
}

variable "data_subnet_ids" {
  description = "The two data-tier subnet IDs from the network module (values(module.network.data_subnet_ids))."
  type        = list(string)

  validation {
    condition     = length(var.data_subnet_ids) == 2
    error_message = "Expected exactly 2 data subnets (one per AZ), matching the network module's fixed subnet design."
  }
}

variable "security_group_id" {
  description = "The data-tier security group ID from the network module (module.network.data_security_group_id) — already scoped to allow Postgres/Redis inbound from the app tier only. This module does not create its own SG."
  type        = string
}

variable "multi_az" {
  description = "No default — every environment's terraform.tfvars sets this explicitly. true in prod (synchronous standby + automatic failover), false in dev/staging (cost, nothing there needs to survive an AZ outage)."
  type        = bool
}

variable "engine_version" {
  description = "Pinned minor version, verified live against AWS's available RDS Postgres 16 versions. auto_minor_version_upgrade handles patching going forward."
  type        = string
  default     = "16.14"
}

variable "instance_class" {
  type    = string
  default = "db.t4g.micro"
}

variable "allocated_storage" {
  type    = number
  default = 20
}

variable "max_allocated_storage" {
  description = "Enables RDS storage autoscaling up to this ceiling (GB)."
  type        = number
  default     = 100
}

variable "db_name" {
  type    = string
  default = "app"
}

variable "master_username" {
  type    = string
  default = "appadmin"
}

variable "backup_retention_period" {
  description = "Days. Kept short by default (cost); prod's terraform.tfvars should raise this."
  type        = number
  default     = 1
}

variable "deletion_protection" {
  description = "false by default so this can be torn down cleanly. Prod's terraform.tfvars should set this to true."
  type        = bool
  default     = false
}

variable "skip_final_snapshot" {
  description = "true by default (fast, cheap teardown for dev/staging). Prod's terraform.tfvars should set this to false and rely on final_snapshot_identifier."
  type        = bool
  default     = true
}

variable "tags" {
  type    = map(string)
  default = {}
}
