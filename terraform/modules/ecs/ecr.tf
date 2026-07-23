# Repos only - Terraform never pushes an image or owns a tag. GitHub
# Actions (Phase 5) pushes here under an immutable SHA tag and a moving
# :prod/:staging tag; this module's task definitions reference the moving
# tag once real images exist (see the placeholder-image comment in
# variables.tf).

resource "aws_ecr_repository" "fastapi" {
  name                 = "${var.project_name}-${var.environment}-fastapi"
  image_tag_mutability = "MUTABLE" # required for a moving tag like :prod
  force_delete         = var.ecr_force_delete

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = var.tags
}

resource "aws_ecr_repository" "celery" {
  name                 = "${var.project_name}-${var.environment}-celery"
  image_tag_mutability = "MUTABLE"
  force_delete         = var.ecr_force_delete

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = var.tags
}

# Untagged images (superseded when :prod/:staging moves to a new digest)
# expire after a week instead of accumulating storage cost forever. A
# count-based rule for SHA-tagged images can be added once Phase 5
# establishes the real tagging pattern in practice.
locals {
  ecr_lifecycle_policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images older than 7 days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 7
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

resource "aws_ecr_lifecycle_policy" "fastapi" {
  repository = aws_ecr_repository.fastapi.name
  policy     = local.ecr_lifecycle_policy
}

resource "aws_ecr_lifecycle_policy" "celery" {
  repository = aws_ecr_repository.celery.name
  policy     = local.ecr_lifecycle_policy
}
