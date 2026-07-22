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
  description = "Jaeger/Flower/Flagsmith admin UIs - reachable directly at these addresses once connected via the Cloudflare WARP client and granted a one-time PIN (cloudflare_zero_trust_access_application.warp_enrollment). No public hostname involved."
  value = {
    flagsmith = "http://${var.flagsmith_private_ip}:${var.flagsmith_port}"
    flower    = "http://${var.flower_private_ip}:${var.flower_port}"
    jaeger    = "http://${var.jaeger_private_ip}:${var.jaeger_port}"
  }
}
