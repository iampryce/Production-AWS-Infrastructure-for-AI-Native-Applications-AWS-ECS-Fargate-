resource "aws_db_subnet_group" "this" {
  name       = "${var.project_name}-${var.environment}-db-subnet-group"
  subnet_ids = var.data_subnet_ids

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-db-subnet-group"
  })
}

# Explicit parameter group rather than the AWS default — nothing custom
# tuned yet, but this leaves room to change parameters later without a
# resource replacement (default parameter groups can't be modified).
resource "aws_db_parameter_group" "this" {
  name   = "${var.project_name}-${var.environment}-pg16"
  family = "postgres16"

  tags = var.tags
}

# No password ever generated or stored in this Terraform config or state —
# manage_master_user_password = true has RDS create and manage the secret
# in AWS Secrets Manager natively (and rotate it), so it never exists in
# plaintext anywhere Terraform touches.
resource "aws_db_instance" "this" {
  identifier     = "${var.project_name}-${var.environment}-pg"
  engine         = "postgres"
  engine_version = var.engine_version

  instance_class        = var.instance_class
  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  storage_type          = "gp3"
  storage_encrypted     = true

  db_name  = var.db_name
  username = var.master_username

  manage_master_user_password = true

  db_subnet_group_name   = aws_db_subnet_group.this.name
  parameter_group_name   = aws_db_parameter_group.this.name
  vpc_security_group_ids = [var.security_group_id]

  multi_az = var.multi_az

  auto_minor_version_upgrade = true
  backup_retention_period    = var.backup_retention_period
  deletion_protection        = var.deletion_protection
  skip_final_snapshot        = var.skip_final_snapshot
  final_snapshot_identifier  = var.skip_final_snapshot ? null : "${var.project_name}-${var.environment}-pg-final"

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-pg"
  })
}
