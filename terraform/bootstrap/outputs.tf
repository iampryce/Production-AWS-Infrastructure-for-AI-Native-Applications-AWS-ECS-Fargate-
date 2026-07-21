output "state_bucket_name" {
  description = "S3 bucket name to reference in each environment's backend block."
  value       = aws_s3_bucket.terraform_state.id
}

output "aws_region" {
  value = var.aws_region
}
