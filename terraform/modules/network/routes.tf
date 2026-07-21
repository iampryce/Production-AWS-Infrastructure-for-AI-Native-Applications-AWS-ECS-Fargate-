resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-public-rt"
  })
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  for_each       = aws_subnet.public
  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

# One private route table per AZ, shared by the app and data subnets in
# that AZ — both route outbound through the same NAT target, so a single
# table per AZ is enough without losing the app/data subnet split itself.
resource "aws_route_table" "private" {
  for_each = toset(var.azs)
  vpc_id   = aws_vpc.this.id

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-private-rt-${each.key}"
  })
}

resource "aws_route" "private_default" {
  for_each               = aws_route_table.private
  route_table_id         = each.value.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = var.nat_type == "nat-gateway" ? aws_nat_gateway.this[local.nat_target_az_for[each.key]].id : null
  network_interface_id   = var.nat_type == "fck-nat" ? aws_instance.fck_nat[local.nat_target_az_for[each.key]].primary_network_interface_id : null
}

resource "aws_route_table_association" "app" {
  for_each       = aws_subnet.app
  subnet_id      = each.value.id
  route_table_id = aws_route_table.private[each.key].id
}

resource "aws_route_table_association" "data" {
  for_each       = aws_subnet.data
  subnet_id      = each.value.id
  route_table_id = aws_route_table.private[each.key].id
}

# Ops subnet: outbound through NAT too, but never associated with the
# public route table — zero inbound route from the internet gateway.
resource "aws_route_table" "ops" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-ops-rt"
  })
}

resource "aws_route" "ops_default" {
  route_table_id         = aws_route_table.ops.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = var.nat_type == "nat-gateway" ? aws_nat_gateway.this[local.nat_target_az_for[var.ops_az]].id : null
  network_interface_id   = var.nat_type == "fck-nat" ? aws_instance.fck_nat[local.nat_target_az_for[var.ops_az]].primary_network_interface_id : null
}

resource "aws_route_table_association" "ops" {
  subnet_id      = aws_subnet.ops.id
  route_table_id = aws_route_table.ops.id
}
