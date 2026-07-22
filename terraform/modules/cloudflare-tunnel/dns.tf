locals {
  admin_domain = "${var.admin_subdomain}.${var.root_domain}"
  admin_hostnames = [
    "flagsmith.${local.admin_domain}",
    "flower.${local.admin_domain}",
    "jaeger.${local.admin_domain}",
  ]
}

# Cloudflare has to be DNS-authoritative for a hostname before it can
# route it to a tunnel or apply an Access policy - Route 53 stays
# authoritative for the root domain (CloudFront/ACM/the public API depend
# on that), so only this one subdomain gets delegated via NS records,
# below. Everything under it is Cloudflare's problem; everything else
# stays exactly as ADR-007 set it up.
resource "cloudflare_zone" "admin" {
  account = { id = var.cloudflare_account_id }
  name    = local.admin_domain
}

resource "aws_route53_record" "admin_ns_delegation" {
  zone_id = var.route53_zone_id
  name    = var.admin_subdomain
  type    = "NS"
  ttl     = 300
  records = cloudflare_zone.admin.name_servers
}

# Proxied (orange-cloud) CNAMEs to the tunnel's own address - this is what
# makes Cloudflare's edge route these specific hostnames to this specific
# tunnel, and what lets an Access policy sit in front of them below.
resource "cloudflare_dns_record" "admin_tunnel" {
  for_each = toset(local.admin_hostnames)

  zone_id = cloudflare_zone.admin.id
  name    = each.value
  type    = "CNAME"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.this.id}.cfargotunnel.com"
  ttl     = 1
  proxied = true
}
