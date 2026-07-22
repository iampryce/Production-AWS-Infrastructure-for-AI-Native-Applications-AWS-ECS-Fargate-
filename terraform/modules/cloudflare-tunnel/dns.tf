locals {
  admin_records = {
    "flagsmith.admin.${var.root_domain}" = var.flagsmith_private_ip
    "flower.admin.${var.root_domain}"    = var.flower_private_ip
    "jaeger.admin.${var.root_domain}"    = var.jaeger_private_ip
  }
}

# Plain A records pointing at private (RFC1918) IPs, in the same public
# Route 53 zone CloudFront/ACM already use. Publishing a private IP in
# public DNS isn't itself a security boundary - the boundary is that the
# IP is unreachable from the public internet regardless of who looks it
# up, and only a WARP-connected, Access-allowed device can actually route
# to it through the tunnel (tunnel.tf's private network route). This is
# the same pattern as pointing a public hostname at an internal load
# balancer reachable only over a VPN.
resource "aws_route53_record" "admin" {
  for_each = local.admin_records

  zone_id = var.route53_zone_id
  name    = each.key
  type    = "A"
  ttl     = 300
  records = [each.value]
}
