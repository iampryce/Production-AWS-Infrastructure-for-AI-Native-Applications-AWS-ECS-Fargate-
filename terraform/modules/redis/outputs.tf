output "primary_endpoint_address" {
  value = aws_elasticache_replication_group.this.primary_endpoint_address
}

output "reader_endpoint_address" {
  description = "Only meaningful when automatic_failover_enabled = true (a real replica exists)."
  value       = var.automatic_failover_enabled ? aws_elasticache_replication_group.this.reader_endpoint_address : null
}

output "port" {
  value = var.port
}

output "replication_group_id" {
  description = "CloudWatch's AWS/ElastiCache ReplicationGroupId dimension on this."
  value       = aws_elasticache_replication_group.this.id
}

output "auth_token_secret_arn" {
  description = "Secrets Manager secret ARN holding the Redis AUTH token. Reference this from ECS task definitions (Phase 4) via a Secrets Manager data source, not a plain env var."
  value       = aws_secretsmanager_secret.redis_auth_token.arn
}
