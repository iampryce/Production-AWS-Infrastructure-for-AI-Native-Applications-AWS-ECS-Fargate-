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

output "admin_hostnames" {
  description = "Jaeger/Flower/Flagsmith admin UIs, reachable once Cloudflare Access grants a one-time PIN to an allowed email."
  value       = local.admin_hostnames
}

output "admin_zone_name_servers" {
  description = "Confirm these show as NS at the admin subdomain in Route 53 (aws_route53_record.admin_ns_delegation) once the zone activates."
  value       = cloudflare_zone.admin.name_servers
}
