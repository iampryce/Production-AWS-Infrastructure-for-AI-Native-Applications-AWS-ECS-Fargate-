output "instance_id" {
  value = aws_instance.this.id
}

output "private_ip" {
  value = aws_instance.this.private_ip
}

output "iam_role_arn" {
  value = aws_iam_role.this.arn
}

output "tunnel_id" {
  value = cloudflare_zero_trust_tunnel_cloudflared.this.id
}

output "admin_endpoints" {
  description = "Jaeger/Flower/Flagsmith admin UIs - reachable at these hostnames once connected via the Cloudflare WARP client and granted a one-time PIN (cloudflare_zero_trust_access_application.warp_enrollment). Plain Route 53 A records pointing at private IPs - resolvable by anyone, but only routable through the tunnel's private network route."
  value = {
    flagsmith = "http://flagsmith.admin.${var.root_domain}:${var.flagsmith_port}"
    flower    = "http://flower.admin.${var.root_domain}:${var.flower_port}"
    jaeger    = "http://jaeger.admin.${var.root_domain}:${var.jaeger_port}"
  }
}
