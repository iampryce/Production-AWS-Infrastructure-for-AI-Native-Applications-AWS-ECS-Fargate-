data "aws_region" "current" {}

resource "aws_ecs_task_definition" "fastapi" {
  family                   = "${var.project_name}-${var.environment}-fastapi"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.fastapi_cpu
  memory                   = var.fastapi_memory
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.fastapi_task.arn

  container_definitions = jsonencode([
    {
      name  = "fastapi"
      image = var.fastapi_placeholder_image
      # Placeholder command - see the comment on fastapi_placeholder_image
      # in variables.tf. Removed once the real image is wired in.
      command = ["python3", "-m", "http.server", tostring(var.app_port)]

      portMappings = [
        {
          containerPort = var.app_port
          protocol      = "tcp"
        }
      ]

      environment = [
        { name = "DB_HOST", value = var.rds_host },
        { name = "DB_NAME", value = var.rds_db_name },
        { name = "DB_USER", value = var.rds_master_username },
        { name = "REDIS_HOST", value = var.redis_primary_endpoint_address },
        { name = "REDIS_PORT", value = tostring(var.redis_port) },
      ]

      secrets = [
        { name = "DB_SECRET", valueFrom = var.rds_master_user_secret_arn },
        { name = "REDIS_AUTH_SECRET", valueFrom = var.redis_auth_token_secret_arn },
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.fastapi.name
          "awslogs-region"        = data.aws_region.current.name
          "awslogs-stream-prefix" = "fastapi"
        }
      }
    }
  ])

  tags = var.tags
}

resource "aws_ecs_task_definition" "celery" {
  family                   = "${var.project_name}-${var.environment}-celery"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.celery_cpu
  memory                   = var.celery_memory
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.celery_task.arn

  container_definitions = jsonencode([
    {
      name  = "celery"
      image = var.celery_placeholder_image
      # Placeholder command - stays alive, does nothing. See the comment
      # on celery_placeholder_image in variables.tf.
      command = ["sleep", "infinity"]

      environment = [
        { name = "DB_HOST", value = var.rds_host },
        { name = "DB_NAME", value = var.rds_db_name },
        { name = "DB_USER", value = var.rds_master_username },
        { name = "REDIS_HOST", value = var.redis_primary_endpoint_address },
        { name = "REDIS_PORT", value = tostring(var.redis_port) },
      ]

      secrets = [
        { name = "DB_SECRET", valueFrom = var.rds_master_user_secret_arn },
        { name = "REDIS_AUTH_SECRET", valueFrom = var.redis_auth_token_secret_arn },
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.celery.name
          "awslogs-region"        = data.aws_region.current.name
          "awslogs-stream-prefix" = "celery"
        }
      }
    }
  ])

  tags = var.tags
}
