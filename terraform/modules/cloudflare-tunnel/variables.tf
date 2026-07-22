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

# --- Admin subdomain (Jaeger / Flower / Flagsmith, proxied through the tunnel) ---

variable "root_domain" {
  description = "module.cloudfront.domain_name's zone (e.g. \"rivetrecords.online\"). Route 53 stays authoritative for this zone; only the admin subdomain below gets delegated to Cloudflare."
  type        = string
}

variable "route53_zone_id" {
  description = "module.cloudfront.zone_id. Needed to add the NS delegation record for the admin subdomain in the same zone CloudFront/ACM already use."
  type        = string
}

variable "admin_subdomain" {
  description = "Delegated to Cloudflare via NS records so the tunnel's public-hostname routing and Access policies can apply to it. Combines with root_domain, e.g. \"admin\" + \"rivetrecords.online\" = admin.rivetrecords.online."
  type        = string
  default     = "admin"
}

variable "access_allowed_emails" {
  description = "Email addresses allowed through Cloudflare Access (one-time PIN) on every admin hostname. No default - must come from this environment's terraform.tfvars."
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
