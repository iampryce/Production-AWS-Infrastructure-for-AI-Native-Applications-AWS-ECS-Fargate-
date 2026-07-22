# Request path: Route 53 -> CloudFront (WAF attached at the edge) -> ALB
# for everything except /assets/*, which goes to S3 via OAC instead - one
# distribution, two origins, not two separate hops or two distributions.

locals {
  aliases = var.include_www ? [var.domain_name, "www.${var.domain_name}"] : [var.domain_name]
}

resource "aws_cloudfront_distribution" "this" {
  enabled     = true
  aliases     = local.aliases
  web_acl_id  = aws_wafv2_web_acl.this.arn
  price_class = "PriceClass_100" # North America + Europe only - cost-conscious for a demo, not global reach

  origin {
    origin_id   = "alb"
    domain_name = var.alb_dns_name

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only" # No HTTPS listener on the ALB yet - it's behind CloudFront's own TLS termination
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  origin {
    origin_id                = "assets"
    domain_name              = aws_s3_bucket.assets.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.assets.id
  }

  # Default behavior: everything goes to the ALB (dynamic, uncached).
  default_cache_behavior {
    target_origin_id       = "alb"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods         = ["GET", "HEAD"]

    forwarded_values {
      query_string = true
      headers      = ["*"]

      cookies {
        forward = "all"
      }
    }

    min_ttl     = 0
    default_ttl = 0
    max_ttl     = 0
  }

  # Generated assets: cached, served from S3 via OAC.
  ordered_cache_behavior {
    path_pattern           = "/assets/*"
    target_origin_id       = "assets"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    min_ttl     = 0
    default_ttl = 86400
    max_ttl     = 31536000
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate_validation.this.certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  tags = var.tags
}

resource "aws_route53_record" "apex_alias" {
  zone_id = aws_route53_zone.this.zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.this.domain_name
    zone_id                = aws_cloudfront_distribution.this.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "www_alias" {
  count = var.include_www ? 1 : 0

  zone_id = aws_route53_zone.this.zone_id
  name    = "www.${var.domain_name}"
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.this.domain_name
    zone_id                = aws_cloudfront_distribution.this.hosted_zone_id
    evaluate_target_health = false
  }
}
