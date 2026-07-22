output "instance_id" {
  value = aws_instance.this.id
}

output "private_ip" {
  value = aws_instance.this.private_ip
}

output "db_instance_id" {
  value = aws_db_instance.flagsmith.id
}

output "db_master_user_secret_arn" {
  value = aws_db_instance.flagsmith.master_user_secret[0].secret_arn
}
