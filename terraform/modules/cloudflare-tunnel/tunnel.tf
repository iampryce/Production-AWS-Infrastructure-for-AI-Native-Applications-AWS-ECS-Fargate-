# Terraform owns the tunnel's full lifecycle via the Cloudflare provider -
# traceable in state and git, not a value pasted in once from the dashboard.
# The provider reads its credential from the CLOUDFLARE_API_TOKEN env var
# (set in CI, never committed) the same way the aws provider reads AWS
# credentials - no token value appears in any .tf file or tfvars.

# config_src = "cloudflare": ingress rules are owned by the
# cloudflare_zero_trust_tunnel_cloudflared_config resource below and live
# in Terraform state, not in a hand-maintained file on the instance. A
# routing change (adding another admin hostname, repointing a service)
# is then a normal plan/apply diff instead of requiring the EC2 instance
# to reboot and re-read a local file - still fully Terraform-owned end to
# end via the Cloudflare provider, just via the API-managed path rather
# than a local config.yml. tunnel_secret must be >=32 bytes,
# base64-encoded - random_id's b64_std output satisfies that directly.
resource "random_id" "tunnel_secret" {
  byte_length = 32
}

resource "cloudflare_zero_trust_tunnel_cloudflared" "this" {
  account_id    = var.cloudflare_account_id
  name          = "${var.project_name}-${var.environment}-ops-tunnel"
  config_src    = "cloudflare"
  tunnel_secret = random_id.tunnel_secret.b64_std
}

# The connector token cloudflared needs at boot to authenticate itself -
# derived from the tunnel above, not a second independently-created secret.
data "cloudflare_zero_trust_tunnel_cloudflared_token" "this" {
  account_id = var.cloudflare_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.this.id
}

# Ingress rules for the three ops-subnet admin UIs, proxied through the
# tunnel to their private IPs. Each entry needs its own hostname match;
# the final catch-all returns a plain 404 for anything that doesn't match
# one of the named hostnames, rather than silently proxying to whatever
# service happens to be listed first.
resource "cloudflare_zero_trust_tunnel_cloudflared_config" "this" {
  account_id = var.cloudflare_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.this.id

  config = {
    ingress = [
      {
        hostname = "flagsmith.${local.admin_domain}"
        service  = "http://${var.flagsmith_private_ip}:${var.flagsmith_port}"
      },
      {
        hostname = "flower.${local.admin_domain}"
        service  = "http://${var.flower_private_ip}:${var.flower_port}"
      },
      {
        hostname = "jaeger.${local.admin_domain}"
        service  = "http://${var.jaeger_private_ip}:${var.jaeger_port}"
      },
      {
        service = "http_status:404"
      },
    ]
  }
}
