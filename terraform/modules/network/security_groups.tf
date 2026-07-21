# Chain: ALB (internet) -> App (ALB only) -> Data (App only). Ops has no
# internet-facing inbound rule at all — reached only via the Cloudflare
# Tunnel's outbound connection, established from inside the ops subnet.
#
# Rules are separate aws_vpc_security_group_*_rule resources rather than
# inline ingress/egress blocks — ALB and App reference each other's SG IDs,
# and inline blocks on both sides create a dependency cycle Terraform can't
# resolve. Separate rule resources are also the pattern the AWS provider
# has recommended since v5.

resource "aws_security_group" "alb" {
  name        = "${var.project_name}-${var.environment}-alb-sg"
  description = "Internet-facing ALB"
  vpc_id      = aws_vpc.this.id
  tags        = var.tags
}

resource "aws_security_group" "app" {
  name        = "${var.project_name}-${var.environment}-app-sg"
  description = "FastAPI + Celery ECS Fargate tasks"
  vpc_id      = aws_vpc.this.id
  tags        = var.tags
}

resource "aws_security_group" "data" {
  name        = "${var.project_name}-${var.environment}-data-sg"
  description = "RDS Postgres + ElastiCache Redis"
  vpc_id      = aws_vpc.this.id
  tags        = var.tags
}

resource "aws_security_group" "ops" {
  name        = "${var.project_name}-${var.environment}-ops-sg"
  description = "Cloudflare Tunnel EC2, Flagsmith, OTel collector, Flower — no internet-facing inbound rule"
  vpc_id      = aws_vpc.this.id
  tags        = var.tags
}

# --- ALB ---

resource "aws_vpc_security_group_ingress_rule" "alb_https_from_internet" {
  security_group_id = aws_security_group.alb.id
  description        = "HTTPS from the internet"
  from_port          = 443
  to_port            = 443
  ip_protocol        = "tcp"
  cidr_ipv4          = "0.0.0.0/0"
}

resource "aws_vpc_security_group_ingress_rule" "alb_http_from_internet" {
  security_group_id = aws_security_group.alb.id
  description        = "HTTP from the internet (redirected to HTTPS at the listener)"
  from_port          = 80
  to_port            = 80
  ip_protocol        = "tcp"
  cidr_ipv4          = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "alb_to_app" {
  security_group_id            = aws_security_group.alb.id
  description                   = "To the app tier only"
  from_port                     = var.app_port
  to_port                       = var.app_port
  ip_protocol                   = "tcp"
  referenced_security_group_id  = aws_security_group.app.id
}

# --- App ---

resource "aws_vpc_security_group_ingress_rule" "app_from_alb" {
  security_group_id            = aws_security_group.app.id
  description                   = "From the ALB only"
  from_port                     = var.app_port
  to_port                       = var.app_port
  ip_protocol                   = "tcp"
  referenced_security_group_id  = aws_security_group.alb.id
}

resource "aws_vpc_security_group_egress_rule" "app_to_anywhere" {
  security_group_id = aws_security_group.app.id
  description        = "Data tier, ops tier, and the internet (AI providers, ECR, etc.) via NAT"
  ip_protocol        = "-1"
  cidr_ipv4          = "0.0.0.0/0"
}

# --- Data ---

resource "aws_vpc_security_group_ingress_rule" "data_postgres_from_app" {
  security_group_id            = aws_security_group.data.id
  description                   = "Postgres from the app tier only"
  from_port                     = var.postgres_port
  to_port                       = var.postgres_port
  ip_protocol                   = "tcp"
  referenced_security_group_id  = aws_security_group.app.id
}

resource "aws_vpc_security_group_ingress_rule" "data_redis_from_app" {
  security_group_id            = aws_security_group.data.id
  description                   = "Redis from the app tier only"
  from_port                     = var.redis_port
  to_port                       = var.redis_port
  ip_protocol                   = "tcp"
  referenced_security_group_id  = aws_security_group.app.id
}

resource "aws_vpc_security_group_egress_rule" "data_to_anywhere" {
  security_group_id = aws_security_group.data.id
  ip_protocol        = "-1"
  cidr_ipv4          = "0.0.0.0/0"
}

# --- Ops ---

resource "aws_vpc_security_group_ingress_rule" "ops_flagsmith_from_app" {
  security_group_id            = aws_security_group.ops.id
  description                   = "Flagsmith API from the app tier"
  from_port                     = var.flagsmith_port
  to_port                       = var.flagsmith_port
  ip_protocol                   = "tcp"
  referenced_security_group_id  = aws_security_group.app.id
}

resource "aws_vpc_security_group_ingress_rule" "ops_otel_from_app" {
  security_group_id            = aws_security_group.ops.id
  description                   = "OTel collector (gRPC + HTTP) from the app tier"
  from_port                     = 4317
  to_port                       = 4318
  ip_protocol                   = "tcp"
  referenced_security_group_id  = aws_security_group.app.id
}

resource "aws_vpc_security_group_egress_rule" "ops_to_anywhere" {
  security_group_id = aws_security_group.ops.id
  description        = "Outbound only — the Cloudflare Tunnel connection is initiated from here, never inbound"
  ip_protocol        = "-1"
  cidr_ipv4          = "0.0.0.0/0"
}
