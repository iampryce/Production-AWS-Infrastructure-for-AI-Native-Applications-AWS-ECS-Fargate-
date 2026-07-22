data "aws_region" "current" {}

locals {
  # Real images (built from backend/Dockerfile, workers/Dockerfile in
  # Phase 5) already bake the equivalent placeholder command into their
  # own Dockerfile CMD, so no command override is needed once
  # use_placeholder_images = false - only the raw python:3.12-slim image
  # pulled directly from Docker Hub needs one. `null` here (rather than
  # conditionally omitting the key via merge()) is deliberate: Terraform's
  # type checker requires both branches of a conditional object to share
  # the same shape, but happily unifies a list(string) with null - and the
  # AWS provider treats a null container_definitions field as omitted when
  # it builds the actual RegisterTaskDefinition call, not as a literal
  # empty command.
  fastapi_image   = var.use_placeholder_images ? var.fastapi_placeholder_image : "${aws_ecr_repository.fastapi.repository_url}:prod"
  celery_image    = var.use_placeholder_images ? var.celery_placeholder_image : "${aws_ecr_repository.celery.repository_url}:prod"
  fastapi_command = var.use_placeholder_images ? ["python3", "-m", "http.server", tostring(var.app_port)] : null
  celery_command  = var.use_placeholder_images ? ["sleep", "infinity"] : null
}

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
      name    = "fastapi"
      image   = local.fastapi_image
      command = local.fastapi_command

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
      name    = "celery"
      image   = local.celery_image
      command = local.celery_command

      environment = [
        { name = "DB_HOST", value = var.rds_host },
        { name = "DB_NAME", value = var.rds_db_name },
        { name = "DB_USER", value = var.rds_master_username },
        { name = "REDIS_HOST", value = var.redis_primary_endpoint_address },
        { name = "REDIS_PORT", value = tostring(var.redis_port) },
        { name = "ASSETS_BUCKET_NAME", value = var.assets_bucket_name },
        { name = "PUBLIC_ASSET_BASE_URL", value = var.public_asset_base_url },
      ]

      secrets = [
        { name = "DB_SECRET", valueFrom = var.rds_master_user_secret_arn },
        { name = "REDIS_AUTH_SECRET", valueFrom = var.redis_auth_token_secret_arn },
        { name = "OPENAI_API_KEY", valueFrom = aws_secretsmanager_secret.openai_api_key.arn },
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
