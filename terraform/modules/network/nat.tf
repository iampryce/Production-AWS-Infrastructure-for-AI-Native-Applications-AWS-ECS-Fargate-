locals {
  primary_az = var.azs[0]

  # Which AZs actually get a NAT resource, per the active strategy.
  nat_gateway_azs = var.nat_type == "nat-gateway" ? toset(var.azs) : toset([])
  fck_nat_azs     = var.nat_type == "fck-nat" ? (var.fck_nat_ha ? toset(var.azs) : toset([local.primary_az])) : toset([])

  # Every AZ's outbound route resolves to a NAT target. In fck-nat non-HA
  # mode both AZs deliberately resolve to the single primary-AZ instance.
  nat_target_az_for = {
    for az in var.azs : az => (
      var.nat_type == "fck-nat" && !var.fck_nat_ha ? local.primary_az : az
    )
  }
}

# ---------------------------------------------------------------------------
# Real managed NAT Gateway — prod. One per AZ, no shared single point of
# failure.
# ---------------------------------------------------------------------------

resource "aws_eip" "nat" {
  for_each = local.nat_gateway_azs
  domain   = "vpc"

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-nat-eip-${each.key}"
  })
}

resource "aws_nat_gateway" "this" {
  for_each      = local.nat_gateway_azs
  allocation_id = aws_eip.nat[each.key].id
  subnet_id     = aws_subnet.public[each.key].id

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-natgw-${each.key}"
  })

  depends_on = [aws_internet_gateway.this]
}

# ---------------------------------------------------------------------------
# fck-nat — dev/staging cost optimization. AMI lookup verified live against
# the official fck-nat publisher account (568608671756) rather than a
# hardcoded/guessed ID; override with fck_nat_ami_id to pin a specific build.
# ---------------------------------------------------------------------------

data "aws_ami" "fck_nat" {
  count       = var.nat_type == "fck-nat" && var.fck_nat_ami_id == null ? 1 : 0
  most_recent = true
  owners      = ["568608671756"]

  filter {
    name   = "name"
    values = ["fck-nat-al2023-hvm-*-arm64-ebs"]
  }
}

locals {
  fck_nat_ami_id = var.fck_nat_ami_id != null ? var.fck_nat_ami_id : (
    length(data.aws_ami.fck_nat) > 0 ? data.aws_ami.fck_nat[0].id : null
  )
}

resource "aws_security_group" "fck_nat" {
  count       = var.nat_type == "fck-nat" ? 1 : 0
  name        = "${var.project_name}-${var.environment}-fck-nat-sg"
  description = "Allows NAT traffic from inside the VPC to the fck-nat instance(s)"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "All traffic from inside the VPC"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "To the internet"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = var.tags
}

data "aws_iam_policy_document" "fck_nat_assume_role" {
  count = var.nat_type == "fck-nat" ? 1 : 0

  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

# SSM Session Manager access instead of SSH/a bastion — consistent with the
# no-public-bastion stance used everywhere else in this architecture.
resource "aws_iam_role" "fck_nat" {
  count              = var.nat_type == "fck-nat" ? 1 : 0
  name               = "${var.project_name}-${var.environment}-fck-nat-role"
  assume_role_policy = data.aws_iam_policy_document.fck_nat_assume_role[0].json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "fck_nat_ssm" {
  count      = var.nat_type == "fck-nat" ? 1 : 0
  role       = aws_iam_role.fck_nat[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "fck_nat" {
  count = var.nat_type == "fck-nat" ? 1 : 0
  name  = "${var.project_name}-${var.environment}-fck-nat-profile"
  role  = aws_iam_role.fck_nat[0].name
}

resource "aws_instance" "fck_nat" {
  for_each                    = local.fck_nat_azs
  ami                         = local.fck_nat_ami_id
  instance_type               = var.fck_nat_instance_type
  subnet_id                   = aws_subnet.public[each.key].id
  vpc_security_group_ids      = [aws_security_group.fck_nat[0].id]
  iam_instance_profile        = aws_iam_instance_profile.fck_nat[0].name
  source_dest_check           = false
  associate_public_ip_address = true

  lifecycle {
    precondition {
      condition     = var.nat_type != "fck-nat" || local.fck_nat_ami_id != null
      error_message = "Could not resolve an fck-nat AMI ID. Either the live AMI lookup failed (check region/owner filter) or fck_nat_ami_id was set to an unexpected value."
    }
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-fck-nat-${each.key}"
  })
}

resource "aws_eip" "fck_nat" {
  for_each = local.fck_nat_azs
  domain   = "vpc"
  instance = aws_instance.fck_nat[each.key].id

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-fck-nat-eip-${each.key}"
  })
}
