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
  description = "The data-tier security group ID from the network module (module.network.data_security_group_id) — already scoped to allow Redis inbound from the app tier only. This module does not create its own SG."
  type        = string
}

variable "automatic_failover_enabled" {
  description = "No default — every environment's terraform.tfvars sets this explicitly. true in prod (primary in AZ-a, replica in AZ-b, automatic failover), false in dev/staging (single node, cost — nothing there needs to survive an AZ outage). Drives node count: true = 2 cache clusters, false = 1."
  type        = bool
}

variable "engine_version" {
  description = "Verified live against AWS's available ElastiCache Redis versions."
  type        = string
  default     = "7.1"
}

variable "parameter_group_family" {
  type    = string
  default = "redis7"
}

variable "node_type" {
  description = "Graviton (arm64) by default, matching the cost-conscious instance family choice used elsewhere in this project (fck-nat, RDS)."
  type        = string
  default     = "cache.t4g.micro"
}

variable "port" {
  type    = number
  default = 6379
}

variable "snapshot_retention_limit" {
  description = "Days of automated snapshots. 0 (default) disables them — cost-conscious for a short-lived environment. Prod's terraform.tfvars should raise this."
  type        = number
  default     = 0
}

variable "tags" {
  type    = map(string)
  default = {}
}
