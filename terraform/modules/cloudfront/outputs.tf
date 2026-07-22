output "zone_id" {
  value = aws_route53_zone.this.zone_id
}

output "zone_name_servers" {
  description = "Update the domain's nameservers at the registrar (Namecheap) to exactly these, then wait for propagation before step 2 (ACM validation + CloudFront) can succeed."
  value       = aws_route53_zone.this.name_servers
}

output "certificate_arn" {
  description = "Validated (step 2)."
  value       = aws_acm_certificate_validation.this.certificate_arn
}

output "cloudfront_domain_name" {
  value = aws_cloudfront_distribution.this.domain_name
}

output "cloudfront_distribution_id" {
  value = aws_cloudfront_distribution.this.id
}

output "assets_bucket_name" {
  value = aws_s3_bucket.assets.id
}

output "site_url" {
  value = "https://${var.domain_name}"
}
