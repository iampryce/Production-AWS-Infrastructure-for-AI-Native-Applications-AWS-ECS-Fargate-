# Deliberately not the shared "data" security group from the network
# module - that one's ingress is App-tier-only by design (CLAUDE.md item
# 3), and Flagsmith's database is only ever reached by Flagsmith's own EC2
# instance in the ops subnet, never directly by FastAPI/Celery. A separate,
# purpose-built SG keeps that invariant on the shared data SG intact. See
# ADR-009 for the full reasoning on why this DB lives in the data subnets
# at all despite being "Flagsmith's ops-subnet database."
resource "aws_security_group" "flagsmith_db" {
  name        = "${var.project_name}-${var.environment}-flagsmith-db-sg"
  description = "Flagsmith own Postgres instance - reachable only from the ops SG"
  vpc_id      = var.vpc_id
  tags        = var.tags
}

resource "aws_vpc_security_group_ingress_rule" "flagsmith_db_from_ops" {
  security_group_id            = aws_security_group.flagsmith_db.id
  description                  = "Postgres from the Flagsmith EC2 instance (ops SG) only"
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
  referenced_security_group_id = var.ops_security_group_id
}

resource "aws_vpc_security_group_egress_rule" "flagsmith_db_to_anywhere" {
  security_group_id = aws_security_group.flagsmith_db.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}
