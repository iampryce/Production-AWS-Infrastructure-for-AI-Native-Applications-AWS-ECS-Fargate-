output "state_bucket_name" {
  description = "S3 bucket name to reference in each environment's backend block."
  value       = aws_s3_bucket.terraform_state.id
}

output "aws_region" {
  value = var.aws_region
}

output "github_actions_plan_role_arn" {
  description = "Set as AWS_ROLE_ARN_PLAN in the GitHub repo (or reference directly in the workflow)."
  value       = aws_iam_role.github_plan.arn
}

output "github_actions_apply_role_arn" {
  description = "Set as AWS_ROLE_ARN_APPLY in the GitHub repo. Only assumable from the main branch."
  value       = aws_iam_role.github_apply.arn
}

output "github_actions_deploy_role_arn" {
  description = "Set as AWS_ROLE_ARN_DEPLOY in the GitHub repo. Scoped to ECR push + ecs:UpdateService only, main branch only."
  value       = aws_iam_role.github_deploy.arn
}
