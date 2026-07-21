resource "aws_subnet" "public" {
  for_each                = var.public_subnet_cidrs
  vpc_id                  = aws_vpc.this.id
  cidr_block              = each.value
  availability_zone       = each.key
  map_public_ip_on_launch = true

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-public-${each.key}"
    Tier = "public"
  })
}

resource "aws_subnet" "app" {
  for_each          = var.app_subnet_cidrs
  vpc_id            = aws_vpc.this.id
  cidr_block        = each.value
  availability_zone = each.key

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-app-${each.key}"
    Tier = "app"
  })
}

resource "aws_subnet" "data" {
  for_each          = var.data_subnet_cidrs
  vpc_id            = aws_vpc.this.id
  cidr_block        = each.value
  availability_zone = each.key

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-data-${each.key}"
    Tier = "data"
  })
}

# Single AZ, deliberate — see ADR-001.
resource "aws_subnet" "ops" {
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.ops_subnet_cidr
  availability_zone = var.ops_az

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-ops"
    Tier = "ops"
  })
}
