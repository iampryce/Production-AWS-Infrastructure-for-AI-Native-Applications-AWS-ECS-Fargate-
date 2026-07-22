# Gates WARP enrollment itself, not a hostname - there's no public URL
# for Jaeger/Flower/Flagsmith to gate (see tunnel.tf). Without this, the
# private network route above would let *any* WARP-connected device
# reach the ops subnet; this policy is what limits who's allowed to
# enroll a device into this Zero Trust org at all.
resource "cloudflare_zero_trust_access_application" "warp_enrollment" {
  account_id       = var.cloudflare_account_id
  name             = "${var.project_name}-${var.environment}-warp-enrollment"
  type             = "warp"
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
