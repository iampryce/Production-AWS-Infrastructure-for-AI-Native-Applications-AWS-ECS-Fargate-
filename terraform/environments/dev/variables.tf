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
