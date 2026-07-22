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

# --- Admin access (Jaeger / Flower / Flagsmith, via WARP private network routing) ---

variable "ops_subnet_cidr" {
  description = "module.network.ops_subnet_cidr. Advertised as a private network route through the tunnel so WARP-connected, Access-allowed devices can reach it directly."
  type        = string
}

# Friendly hostnames for the private IPs below - plain Route 53 A records
# in the same zone CloudFront/ACM already use. This works because WARP
# routes by destination IP, not by which DNS server answered the lookup -
# unlike the abandoned public-hostname design, nothing here needs
# Cloudflare to be DNS-authoritative for anything.
variable "root_domain" {
  description = "module.cloudfront.domain_name's zone (e.g. \"rivetrecords.online\")."
  type        = string
}

variable "route53_zone_id" {
  description = "module.cloudfront.zone_id. Same zone CloudFront/ACM already use - these are just three more records in it."
  type        = string
}

variable "access_allowed_emails" {
  description = "Email addresses allowed to enroll a device in WARP (one-time PIN). No default - must come from this environment's terraform.tfvars."
  type        = list(string)
}

variable "flagsmith_private_ip" {
  description = "module.flagsmith.private_ip"
  type        = string
}

variable "flagsmith_port" {
  description = "Must match the flagsmith module's own flagsmith_port."
  type        = number
  default     = 8000
}

variable "flower_private_ip" {
  description = "module.monitoring.flower_private_ip"
  type        = string
}

variable "flower_port" {
  description = "Must match the monitoring module's own flower_port."
  type        = number
  default     = 5555
}

variable "jaeger_private_ip" {
  description = "module.monitoring.otel_collector_private_ip - Jaeger runs as the second container on the same instance as the OTel collector."
  type        = string
}

variable "jaeger_port" {
  type    = number
  default = 16686
}

variable "tags" {
  type    = map(string)
  default = {}
}
