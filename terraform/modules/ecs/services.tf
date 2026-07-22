resource "aws_ecs_service" "fastapi" {
  name            = "${var.project_name}-${var.environment}-fastapi"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.fastapi.arn
  desired_count   = var.fastapi_desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.app_subnet_ids
    security_groups  = [var.app_security_group_id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.fastapi.arn
    container_name   = "fastapi"
    container_port   = var.app_port
  }

  depends_on = [aws_lb_listener.http]

  tags = var.tags
}

# No load_balancer block - Celery is a background worker, not
# HTTP-facing. Same subnets/SG as FastAPI (both are "app tier").
resource "aws_ecs_service" "celery" {
  name            = "${var.project_name}-${var.environment}-celery"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.celery.arn
  desired_count   = var.celery_desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.app_subnet_ids
    security_groups  = [var.app_security_group_id]
    assign_public_ip = false
  }

  tags = var.tags
}
