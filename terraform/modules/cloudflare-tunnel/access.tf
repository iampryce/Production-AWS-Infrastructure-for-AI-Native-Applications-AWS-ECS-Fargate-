# The tunnel/DNS config above only gets traffic to the right private IP -
# none of Jaeger, Flower, or Flagsmith's admin UI has its own login, so
# without this, the hostname alone would be enough to open any of them.
# One wildcard Access application covers all three admin hostnames with a
# single inline policy, rather than three separate applications that
# could drift out of sync with each other.
resource "cloudflare_zero_trust_access_application" "admin" {
  account_id       = var.cloudflare_account_id
  name             = "${var.project_name}-${var.environment}-admin-tools"
  domain           = "*.${local.admin_domain}"
  type             = "self_hosted"
  session_duration = "24h"

  policies = [
    {
      name     = "Allowed emails - one-time PIN"
      decision = "allow"
      include = [
        for email in var.access_allowed_emails : { email = { email = email } }
      ]
    }
  ]
}
