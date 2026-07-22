# CPU-based target tracking for both services - the one metric that
# applies equally to an HTTP-facing service and a background worker.
# ALB request count only makes sense for FastAPI and would leave Celery
# without a comparable signal; memory-based tracking was the other
# candidate but this workload is expected to be CPU-bound (request
# handling and task processing), not memory-bound. See ADR-005.

resource "aws_appautoscaling_target" "fastapi" {
  service_namespace  = "ecs"
  resource_id        = "service/${aws_ecs_cluster.this.name}/${aws_ecs_service.fastapi.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  min_capacity       = var.fastapi_desired_count
  max_capacity       = var.fastapi_autoscaling_max_capacity
}

resource "aws_appautoscaling_policy" "fastapi_cpu" {
  name               = "${var.project_name}-${var.environment}-fastapi-cpu"
  policy_type        = "TargetTrackingScaling"
  service_namespace  = aws_appautoscaling_target.fastapi.service_namespace
  resource_id        = aws_appautoscaling_target.fastapi.resource_id
  scalable_dimension = aws_appautoscaling_target.fastapi.scalable_dimension

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value       = 70
    scale_in_cooldown  = 300
    scale_out_cooldown = 60
  }
}

resource "aws_appautoscaling_target" "celery" {
  service_namespace  = "ecs"
  resource_id        = "service/${aws_ecs_cluster.this.name}/${aws_ecs_service.celery.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  min_capacity       = var.celery_desired_count
  max_capacity       = var.celery_autoscaling_max_capacity
}

resource "aws_appautoscaling_policy" "celery_cpu" {
  name               = "${var.project_name}-${var.environment}-celery-cpu"
  policy_type        = "TargetTrackingScaling"
  service_namespace  = aws_appautoscaling_target.celery.service_namespace
  resource_id        = aws_appautoscaling_target.celery.resource_id
  scalable_dimension = aws_appautoscaling_target.celery.scalable_dimension

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value       = 70
    scale_in_cooldown  = 300
    scale_out_cooldown = 60
  }
}
