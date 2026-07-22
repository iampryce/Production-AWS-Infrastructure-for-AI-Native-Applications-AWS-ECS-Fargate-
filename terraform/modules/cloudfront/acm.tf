# CloudFront requires the certificate to exist in us-east-1 regardless of
# the stack's actual region - hence the aliased provider.
resource "aws_acm_certificate" "this" {
  provider = aws.us_east_1

  domain_name               = var.domain_name
  subject_alternative_names = var.include_www ? ["www.${var.domain_name}"] : []
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = var.tags
}

# Creating these DNS records doesn't block on anything - they just sit in
# the zone. Actually *waiting* for ACM to see them and mark the
# certificate issued is step 2's aws_acm_certificate_validation resource,
# deliberately left out of this step: that resource polls until validated,
# which can't succeed until the domain's nameservers at the registrar
# have been repointed at this zone (see the zone_name_servers output) and
# that delegation has propagated - not something to block a CI apply job
# waiting on.
resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.this.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  zone_id = aws_route53_zone.this.zone_id
  name    = each.value.name
  type    = each.value.type
  records = [each.value.record]
  ttl     = 300

  allow_overwrite = true
}
