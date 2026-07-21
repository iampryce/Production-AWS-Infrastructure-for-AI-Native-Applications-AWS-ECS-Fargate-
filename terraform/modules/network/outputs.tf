output "vpc_id" {
  value = aws_vpc.this.id
}

output "vpc_cidr" {
  value = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  description = "Map keyed by AZ name."
  value       = { for az, s in aws_subnet.public : az => s.id }
}

output "app_subnet_ids" {
  description = "Map keyed by AZ name."
  value       = { for az, s in aws_subnet.app : az => s.id }
}

output "data_subnet_ids" {
  description = "Map keyed by AZ name."
  value       = { for az, s in aws_subnet.data : az => s.id }
}

output "ops_subnet_id" {
  value = aws_subnet.ops.id
}

output "alb_security_group_id" {
  value = aws_security_group.alb.id
}

output "app_security_group_id" {
  value = aws_security_group.app.id
}

output "data_security_group_id" {
  value = aws_security_group.data.id
}

output "ops_security_group_id" {
  value = aws_security_group.ops.id
}

output "fck_nat_ami_id" {
  description = "Resolved AMI ID actually used (looked up or pinned), null when nat_type = \"nat-gateway\"."
  value       = var.nat_type == "fck-nat" ? local.fck_nat_ami_id : null
}
