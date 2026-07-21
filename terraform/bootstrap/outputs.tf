output "state_bucket_name" {
  description = "S3 bucket name to reference in each environment's backend block."
  value       = aws_s3_bucket.terraform_state.id
}

output "lock_table_name" {
  description = "DynamoDB table name to reference in each environment's backend block."
  value       = aws_dynamodb_table.terraform_locks.name
}

output "aws_region" {
  value = var.aws_region
}
