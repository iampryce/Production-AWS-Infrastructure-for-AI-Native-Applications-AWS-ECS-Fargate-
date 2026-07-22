# WAF for CloudFront must be scope=CLOUDFRONT, which AWS only allows to be
# created in us-east-1 regardless of the distribution's (global) reach -
# same regional requirement as the ACM certificate, same provider alias.
resource "aws_wafv2_web_acl" "this" {
  provider = aws.us_east_1

  name  = "${var.project_name}-${var.environment}-waf"
  scope = "CLOUDFRONT"

  default_action {
    allow {}
  }

  # Two AWS managed rule groups - broad, well-maintained baseline coverage
  # (common web exploits, known-bad request signatures) rather than
  # hand-rolled rules for a project this size.
  rule {
    name     = "AWS-AWSManagedRulesCommonRuleSet"
    priority = 0

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.project_name}-${var.environment}-common"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "AWS-AWSManagedRulesKnownBadInputsRuleSet"
    priority = 1

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.project_name}-${var.environment}-known-bad-inputs"
      sampled_requests_enabled   = true
    }
  }

  # Basic volumetric abuse protection - blocks a single IP once it crosses
  # waf_rate_limit requests in a rolling 5-minute window. Not a substitute
  # for the managed rule sets above (which look at request content), a
  # different, simpler signal on top of them.
  rule {
    name     = "RateLimitPerIp"
    priority = 2

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = var.waf_rate_limit
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.project_name}-${var.environment}-rate-limit"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.project_name}-${var.environment}-waf"
    sampled_requests_enabled   = true
  }

  tags = var.tags
}
