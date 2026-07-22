resource "aws_elasticache_subnet_group" "this" {
  name       = "${var.project_name}-${var.environment}-redis-subnet-group"
  subnet_ids = var.data_subnet_ids

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-redis-subnet-group"
  })
}

# Explicit parameter group rather than the AWS default, same reasoning as
# the RDS module - room to tune parameters later without a replacement.
resource "aws_elasticache_parameter_group" "this" {
  name   = "${var.project_name}-${var.environment}-redis7"
  family = var.parameter_group_family

  tags = var.tags
}

# AUTH token: transit encryption must be enabled to use one at all. There
# is no ElastiCache equivalent of RDS's manage_master_user_password (no
# AWS-managed auth-token lifecycle), so this module generates it and
# stores it in Secrets Manager itself - never hardcoded, never in a plain
# env var, and never logged (random_password.result is marked sensitive).
resource "random_password" "auth_token" {
  length  = 32
  special = true
  # ElastiCache AUTH tokens cannot contain '/', '"', or '@'.
  override_special = "!#$%^&*()-_=+[]{}<>:?"
}

resource "aws_secretsmanager_secret" "redis_auth_token" {
  name = "${var.project_name}-${var.environment}-redis-auth-token"

  # Default deletion behavior schedules a 30-day recovery window instead
  # of deleting immediately - blocks recreating a secret under the same
  # name until it lapses (hit this for real: an earlier failed apply left
  # this exact secret name "scheduled for deletion", and the next apply
  # couldn't create a replacement until it was manually restored and
  # force-deleted). This is an auto-generated token with nothing to
  # recover, and this project is meant to be built and torn down quickly
  # - immediate deletion is the right default here.
  recovery_window_in_days = 0

  tags = var.tags
}

resource "aws_secretsmanager_secret_version" "redis_auth_token" {
  secret_id     = aws_secretsmanager_secret.redis_auth_token.id
  secret_string = random_password.auth_token.result
}

resource "aws_elasticache_replication_group" "this" {
  replication_group_id = "${var.project_name}-${var.environment}-redis"
  description          = "Celery broker and result backend - ${var.environment}"

  engine         = "redis"
  engine_version = var.engine_version
  node_type      = var.node_type
  port           = var.port

  # true (prod): 2 clusters, primary in one AZ + replica in the other,
  # automatic failover and Multi-AZ both on. false (dev/staging): a single
  # node - the documented cost tradeoff, same pattern as fck-nat and RDS.
  num_cache_clusters         = var.automatic_failover_enabled ? 2 : 1
  automatic_failover_enabled = var.automatic_failover_enabled
  multi_az_enabled           = var.automatic_failover_enabled

  subnet_group_name    = aws_elasticache_subnet_group.this.name
  parameter_group_name = aws_elasticache_parameter_group.this.name
  security_group_ids   = [var.security_group_id]

  at_rest_encryption_enabled = true
  transit_encryption_enabled = true
  auth_token                 = random_password.auth_token.result

  snapshot_retention_limit = var.snapshot_retention_limit
  apply_immediately        = true

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-redis"
  })
}
