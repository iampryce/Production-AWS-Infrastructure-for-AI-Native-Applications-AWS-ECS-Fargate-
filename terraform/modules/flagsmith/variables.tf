variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "ops_subnet_id" {
  description = "module.network.ops_subnet_id. The Flagsmith EC2 instance lives here, per CLAUDE.md item 15."
  type        = string
}

variable "ops_security_group_id" {
  description = "module.network.ops_security_group_id. Already allows inbound on flagsmith_port from the App SG (network module's ops_flagsmith_from_app rule) and has no internet-facing inbound rule."
  type        = string
}

# RDS requires a subnet group spanning at least 2 AZs - the single-AZ ops
# subnet can't satisfy that alone. This module's DB lives in the same data
# subnets as the main RDS/Redis instances, but reachable only from the ops
# SG via its own dedicated security group (see security_groups.tf) - not
# the shared "data" SG, which stays App-tier-only per CLAUDE.md item 3.
# See ADR-009.
variable "data_subnet_ids" {
  description = "module.network.data_subnet_ids, as a list. Exactly 2 subnets expected, one per AZ."
  type        = list(string)

  validation {
    condition     = length(var.data_subnet_ids) == 2
    error_message = "Expected exactly 2 data subnets (one per AZ), matching the network module's fixed subnet design."
  }
}

variable "flagsmith_port" {
  description = "Must match the network module's flagsmith_port (the Ops SG's App->Ops ingress rule is already scoped to this port)."
  type        = number
  default     = 8000
}

variable "instance_type" {
  description = "Flagsmith's all-in-one Docker image runs Django + a React frontend in one container - t3.micro is tight for that, t3.small gives real headroom."
  type        = string
  default     = "t3.small"
}

variable "db_instance_class" {
  type    = string
  default = "db.t4g.micro"
}

variable "db_allocated_storage" {
  type    = number
  default = 20
}

variable "db_name" {
  type    = string
  default = "flagsmith"
}

variable "db_master_username" {
  type    = string
  default = "flagsmithadmin"
}

variable "tags" {
  type    = map(string)
  default = {}
}
