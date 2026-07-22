variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "ops_subnet_id" {
  description = "module.network.ops_subnet_id. Single-AZ by deliberate design (see ADR-001)."
  type        = string
}

variable "ops_security_group_id" {
  description = "module.network.ops_security_group_id. Already has no internet-facing inbound rule; this module adds no ingress rules of its own - the tunnel connection is outbound-only."
  type        = string
}

# No default - must come from this environment's terraform.tfvars. Find it
# in the Cloudflare dashboard: Account Home -> right sidebar "Account ID"
# (or `curl -s -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN"
# https://api.cloudflare.com/client/v4/accounts`). Not a secret - it's an
# account identifier, not a credential - so it's a plain variable, not
# Secrets Manager.
variable "cloudflare_account_id" {
  description = "Cloudflare account ID that owns the tunnel."
  type        = string
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "tags" {
  type    = map(string)
  default = {}
}
