output "zone_id" {
  value = aws_route53_zone.this.zone_id
}

output "zone_name_servers" {
  description = "Update the domain's nameservers at the registrar (Namecheap) to exactly these, then wait for propagation before step 2 (ACM validation + CloudFront) can succeed."
  value       = aws_route53_zone.this.name_servers
}

output "certificate_arn" {
  description = "Not yet validated - step 2 adds the aws_acm_certificate_validation resource that waits for that, once DNS delegation has propagated."
  value       = aws_acm_certificate.this.arn
}
