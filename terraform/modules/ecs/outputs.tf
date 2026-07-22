output "cluster_name" {
  value = aws_ecs_cluster.this.name
}

output "alb_dns_name" {
  value = aws_lb.this.dns_name
}

output "fastapi_ecr_repository_url" {
  description = "Point Phase 5's push pipeline here. Task definition's image stays a placeholder until this is wired in."
  value       = aws_ecr_repository.fastapi.repository_url
}

output "celery_ecr_repository_url" {
  value = aws_ecr_repository.celery.repository_url
}

output "fastapi_service_name" {
  value = aws_ecs_service.fastapi.name
}

output "celery_service_name" {
  value = aws_ecs_service.celery.name
}

output "alb_arn_suffix" {
  description = "CloudWatch's AWS/ApplicationELB metrics key on this, not the full ARN."
  value       = aws_lb.this.arn_suffix
}

output "fastapi_target_group_arn_suffix" {
  description = "CloudWatch's AWS/ApplicationELB target group metrics key on this, not the full ARN."
  value       = aws_lb_target_group.fastapi.arn_suffix
}
