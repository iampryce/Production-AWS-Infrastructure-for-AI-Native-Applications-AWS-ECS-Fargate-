data "aws_iam_policy_document" "ecs_tasks_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

# Execution role: used by the ECS agent itself - pulling images from ECR,
# writing container logs to CloudWatch, and resolving the task
# definition's "secrets" block at container start. Not used by the
# application code at runtime; that's the task role below.
resource "aws_iam_role" "execution" {
  name               = "${var.project_name}-${var.environment}-ecs-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume_role.json

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "execution_managed" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# The managed policy above covers ECR pull + CloudWatch Logs, but not
# reading the specific secrets referenced in the task definitions -
# scoped to exactly the two secrets these tasks actually use.
data "aws_iam_policy_document" "execution_secrets" {
  statement {
    actions = ["secretsmanager:GetSecretValue"]
    resources = [
      var.rds_master_user_secret_arn,
      var.redis_auth_token_secret_arn,
    ]
  }
}

resource "aws_iam_role_policy" "execution_secrets" {
  name   = "${var.project_name}-${var.environment}-ecs-execution-secrets"
  role   = aws_iam_role.execution.id
  policy = data.aws_iam_policy_document.execution_secrets.json
}

# Task roles: used by the application code itself at runtime. Separate per
# service (not shared) since FastAPI and Celery will need different AWS
# permissions as later phases add resources (e.g. S3 for generated
# assets) - empty of extra policy today, on purpose, rather than
# pre-granting access to things that don't exist yet.
resource "aws_iam_role" "fastapi_task" {
  name               = "${var.project_name}-${var.environment}-fastapi-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume_role.json

  tags = var.tags
}

resource "aws_iam_role" "celery_task" {
  name               = "${var.project_name}-${var.environment}-celery-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume_role.json

  tags = var.tags
}
