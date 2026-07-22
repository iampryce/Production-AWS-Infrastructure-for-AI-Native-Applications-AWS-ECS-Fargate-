resource "aws_db_subnet_group" "flagsmith" {
  name       = "${var.project_name}-${var.environment}-flagsmith-db-subnet-group"
  subnet_ids = var.data_subnet_ids

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-flagsmith-db-subnet-group"
  })
}

# No custom parameter group - unlike the main RDS module, nothing here is
# expected to need tuned Postgres parameters. Flagsmith's own schema
# migrations run inside the container at startup.

# manage_master_user_password = true, same reasoning as the main RDS
# module: RDS creates and rotates the secret natively, so the password
# never exists in Terraform state or a variable. Deliberately always
# single-AZ, no multi_az variable at all (unlike the main app's RDS/Redis)
# - this is a feature-flag store, not on the critical request path, and
# doesn't warrant the same HA spend even in prod. See ADR-009.
resource "aws_db_instance" "flagsmith" {
  identifier     = "${var.project_name}-${var.environment}-flagsmith-pg"
  engine         = "postgres"
  engine_version = "16.14"

  instance_class    = var.db_instance_class
  allocated_storage = var.db_allocated_storage
  storage_type      = "gp3"
  storage_encrypted = true

  db_name  = var.db_name
  username = var.db_master_username

  manage_master_user_password = true

  db_subnet_group_name   = aws_db_subnet_group.flagsmith.name
  vpc_security_group_ids = [aws_security_group.flagsmith_db.id]

  multi_az = false

  auto_minor_version_upgrade = true
  backup_retention_period    = 1
  deletion_protection        = false
  skip_final_snapshot        = true

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-flagsmith-pg"
  })
}
