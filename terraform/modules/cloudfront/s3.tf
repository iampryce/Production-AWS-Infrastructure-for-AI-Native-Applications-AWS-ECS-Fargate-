# Generated assets (images/messages from Phase 10/11) - private bucket,
# reachable only through CloudFront via Origin Access Control, never
# public directly.

resource "aws_s3_bucket" "assets" {
  bucket        = "${var.project_name}-${var.environment}-assets"
  force_destroy = var.assets_bucket_force_destroy

  tags = var.tags
}

resource "aws_s3_bucket_public_access_block" "assets" {
  bucket = aws_s3_bucket.assets.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "assets" {
  bucket = aws_s3_bucket.assets.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_cloudfront_origin_access_control" "assets" {
  name                              = "${var.project_name}-${var.environment}-assets-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# Scoped to exactly this CloudFront distribution via the SourceArn
# condition - not "any CloudFront distribution in the account."
data "aws_iam_policy_document" "assets_bucket_policy" {
  statement {
    sid     = "AllowCloudFrontOAC"
    actions = ["s3:GetObject"]

    resources = ["${aws_s3_bucket.assets.arn}/*"]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.this.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "assets" {
  bucket = aws_s3_bucket.assets.id
  policy = data.aws_iam_policy_document.assets_bucket_policy.json
}
