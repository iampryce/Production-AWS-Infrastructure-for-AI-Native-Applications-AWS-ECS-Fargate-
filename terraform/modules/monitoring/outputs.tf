output "sns_topic_arn" {
  value = aws_sns_topic.alerts.arn
}

output "otel_collector_instance_id" {
  value = aws_instance.otel_collector.id
}

output "otel_collector_private_ip" {
  value = aws_instance.otel_collector.private_ip
}

output "flower_instance_id" {
  value = aws_instance.flower.id
}

output "flower_private_ip" {
  value = aws_instance.flower.private_ip
}
