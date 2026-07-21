output "db_instance_id" {
  value = aws_db_instance.this.id
}

output "db_endpoint" {
  description = "host:port"
  value       = aws_db_instance.this.endpoint
}

output "db_address" {
  description = "host only, no port"
  value       = aws_db_instance.this.address
}

output "db_name" {
  value = aws_db_instance.this.db_name
}

output "master_username" {
  value = aws_db_instance.this.username
}

output "master_user_secret_arn" {
  description = "Secrets Manager secret ARN holding the master password — RDS-managed, never in Terraform state as plaintext. Reference this from ECS task definitions (Phase 4) via a Secrets Manager data source, not a plain env var."
  value       = aws_db_instance.this.master_user_secret[0].secret_arn
}
