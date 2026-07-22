# Terraform owns the tunnel's full lifecycle via the Cloudflare provider -
# traceable in state and git, not a value pasted in once from the dashboard.
# The provider reads its credential from the CLOUDFLARE_API_TOKEN env var
# (set in CI, never committed) the same way the aws provider reads AWS
# credentials - no token value appears in any .tf file or tfvars.

# Locally-managed tunnel (config_src = "local"): admin access rides on the
# tunnel's private network routing below, not hostname-based ingress
# rules, so there's no remote ingress config for Cloudflare to own here.
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

# Private network routing instead of a public hostname: this Cloudflare
# account's plan doesn't support delegating a subdomain as its own zone
# (confirmed live - the dashboard's "Add a site" flow rejects anything
# but a root domain), so there's no DNS path to a public hostname for
# Jaeger/Flower/Flagsmith. Advertising the ops subnet as a private
# network route means anyone connected via the Cloudflare WARP client -
# gated by the Access application below - can reach those private IPs
# directly, the same way they'd reach any other VPC-internal address.
# No zone, no DNS record, no public URL involved anywhere.
resource "cloudflare_zero_trust_tunnel_cloudflared_route" "ops_subnet" {
  account_id = var.cloudflare_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.this.id
  network    = var.ops_subnet_cidr
  comment    = "Ops subnet - Jaeger/Flower/Flagsmith admin UIs, WARP + Access gated"
}
