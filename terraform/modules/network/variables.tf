variable "project_name" {
  type    = string
  default = "aws-ai-native-infra"
}

variable "environment" {
  description = "dev, staging, or prod. Only used for naming/tags here — NAT type and HA choices are passed in explicitly by the caller, never inferred from this string."
  type        = string
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "azs" {
  description = "Exactly two availability zones — this module implements the fixed 7-subnet design in CLAUDE.md, not an arbitrary N-AZ layout."
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]

  validation {
    condition     = length(var.azs) == 2
    error_message = "This module is built for exactly 2 AZs, per the subnet design in CLAUDE.md."
  }
}

variable "public_subnet_cidrs" {
  description = "Map keyed by AZ name. ALB lives here."
  type        = map(string)
  default = {
    "us-east-1a" = "10.0.0.0/24"
    "us-east-1b" = "10.0.1.0/24"
  }
}

variable "app_subnet_cidrs" {
  description = "Map keyed by AZ name. FastAPI + Celery ECS Fargate services live here."
  type        = map(string)
  default = {
    "us-east-1a" = "10.0.10.0/24"
    "us-east-1b" = "10.0.11.0/24"
  }
}

variable "data_subnet_cidrs" {
  description = "Map keyed by AZ name. RDS + ElastiCache Redis live here."
  type        = map(string)
  default = {
    "us-east-1a" = "10.0.20.0/24"
    "us-east-1b" = "10.0.21.0/24"
  }
}

variable "ops_subnet_cidr" {
  type    = string
  default = "10.0.30.0/24"
}

variable "ops_az" {
  description = "Single AZ for the ops subnet — deliberate, not duplicated across AZs. See ADR-001."
  type        = string
  default     = "us-east-1a"
}

variable "nat_type" {
  description = "\"fck-nat\" or \"nat-gateway\". No default — every environment must declare this explicitly rather than inheriting an implicit choice."
  type        = string

  validation {
    condition     = contains(["fck-nat", "nat-gateway"], var.nat_type)
    error_message = "nat_type must be \"fck-nat\" or \"nat-gateway\"."
  }
}

variable "fck_nat_ha" {
  description = "Only applies when nat_type = \"fck-nat\". false (default) = one shared instance across both AZs — the documented dev/staging cost tradeoff. true = one instance per AZ. Prod must use nat_type = \"nat-gateway\" (always one per AZ) instead of setting this true."
  type        = bool
  default     = false
}

variable "fck_nat_ami_id" {
  description = "Pin a specific fck-nat AMI ID. Leave null (default) to look up the latest arm64 Amazon Linux 2023 build from the official fck-nat publisher account (568608671756, verified live) via a data source. Only relevant when nat_type = \"fck-nat\"."
  type        = string
  default     = null
}

variable "fck_nat_instance_type" {
  description = "Graviton (arm64) by default to match the arm64 AMI lookup — fck-nat is lightweight, no need for anything larger."
  type        = string
  default     = "t4g.micro"
}

variable "app_port" {
  type    = number
  default = 8000
}

variable "postgres_port" {
  type    = number
  default = 5432
}

variable "redis_port" {
  type    = number
  default = 6379
}

variable "flagsmith_port" {
  type    = number
  default = 8000
}

variable "tags" {
  type    = map(string)
  default = {}
}
