# Terraform owns the tunnel's full lifecycle via the Cloudflare provider -
# traceable in state and git, not a value pasted in once from the dashboard.
# The provider reads its credential from the CLOUDFLARE_API_TOKEN env var
# (set in CI, never committed) the same way the aws provider reads AWS
# credentials - no token value appears in any .tf file or tfvars.

# Locally-managed tunnel (config_src = "local"): this instance runs its own
# config.yml rather than routing config living in the Zero Trust dashboard.
# tunnel_secret must be >=32 bytes, base64-encoded - random_id's b64_std
# output satisfies that directly.
resource "random_id" "tunnel_secret" {
  byte_length = 32
}

resource "cloudflare_zero_trust_tunnel_cloudflared" "this" {
  account_id    = var.cloudflare_account_id
  name          = "${var.project_name}-${var.environment}-ops-tunnel"
  config_src    = "local"
  tunnel_secret = random_id.tunnel_secret.b64_std
}

# The connector token cloudflared needs at boot to authenticate itself -
# derived from the tunnel above, not a second independently-created secret.
data "cloudflare_zero_trust_tunnel_cloudflared_token" "this" {
  account_id = var.cloudflare_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.this.id
}
