

variable "github_repo" {
  description = "owner/repo, must match the OIDC trust condition exactly."
  type        = string
  default     = "iampryce/Production-AWS-Infrastructure-for-AI-Native-Applications-AWS-ECS-Fargate-"
}

# Reused, not recreated — AWS allows only one OIDC provider per URL per
# account, and one already exists in this account from a prior project.
data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

# --- Plan role: read-only, usable from any branch/PR ---

data "aws_iam_policy_document" "github_plan_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repo}:*"]
    }
  }
}

resource "aws_iam_role" "github_plan" {
  name               = "${var.project_name}-github-actions-plan"
  assume_role_policy = data.aws_iam_policy_document.github_plan_trust.json
}

resource "aws_iam_role_policy_attachment" "github_plan_readonly" {
  role       = aws_iam_role.github_plan.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

# --- Apply role: read-write, main branch only ---

data "aws_iam_policy_document" "github_apply_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Two independent claims, not one composite sub string. GitHub's OIDC
    # token changes its `sub` claim format to "repo:OWNER/REPO:environment:NAME"
    # whenever the job sets `environment:` (as the apply job does, for the
    # GitHub Environment approval-gate feature) — it stops being
    # "ref:refs/heads/main" the moment environment: is set. Rather than
    # chase that composite format, gate on the environment and ref claims
    # directly; both must match (conditions in one statement are ANDed).
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:environment"
      values   = ["dev"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:ref"
      values   = ["refs/heads/main"]
    }
  }
}

resource "aws_iam_role" "github_apply" {
  name               = "${var.project_name}-github-actions-apply"
  assume_role_policy = data.aws_iam_policy_document.github_apply_trust.json
}

# Scoped to what Phases 0-2 actually need (networking + RDS). Expand this
# policy phase by phase as new modules land (ElastiCache, ECS/ECR,
# CloudFront, Route 53, ACM, Lambda, SNS) rather than granting broad
# service access upfront for things that don't exist yet.
data "aws_iam_policy_document" "github_apply_permissions" {
  statement {
    sid = "NetworkingAndCompute"
    actions = [
      "ec2:*",
    ]
    resources = ["*"]
  }

  statement {
    sid = "RDS"
    actions = [
      "rds:*",
    ]
    resources = ["*"]
  }

  statement {
    sid = "SecretsManagerReadForRdsManagedSecret"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
      "secretsmanager:ListSecrets",
    ]
    resources = ["*"]
  }

  # IAM is scoped to this project's naming prefix only — the apply role can
  # create/manage roles this project needs (e.g. the fck-nat instance role),
  # but can't touch IAM entities outside that prefix. Keeps the blast radius
  # of this CI role bounded even though it needs real IAM write access.
  statement {
    sid = "ScopedIamForProjectRoles"
    actions = [
      "iam:CreateRole",
      "iam:DeleteRole",
      "iam:GetRole",
      "iam:PassRole",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:PutRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:GetRolePolicy",
      "iam:AttachRolePolicy",
      "iam:DetachRolePolicy",
      "iam:ListAttachedRolePolicies",
      "iam:ListRolePolicies",
      "iam:CreateInstanceProfile",
      "iam:DeleteInstanceProfile",
      "iam:GetInstanceProfile",
      "iam:AddRoleToInstanceProfile",
      "iam:RemoveRoleFromInstanceProfile",
      "iam:TagInstanceProfile",
    ]
    resources = [
      "arn:aws:iam::*:role/${var.project_name}-*",
      "arn:aws:iam::*:instance-profile/${var.project_name}-*",
    ]
  }

  statement {
    sid       = "IamReadOnlyForPlan"
    actions   = ["iam:ListRoles", "iam:ListInstanceProfiles"]
    resources = ["*"]
  }

  # Access to this project's own Terraform state bucket only (native S3
  # locking needs read+write on the lockfile object too).
  statement {
    sid = "TerraformStateBucket"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket",
    ]
    resources = [
      aws_s3_bucket.terraform_state.arn,
      "${aws_s3_bucket.terraform_state.arn}/*",
    ]
  }

  statement {
    sid       = "STSIdentity"
    actions   = ["sts:GetCallerIdentity"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "github_apply_permissions" {
  name   = "${var.project_name}-github-actions-apply-permissions"
  role   = aws_iam_role.github_apply.id
  policy = data.aws_iam_policy_document.github_apply_permissions.json
}
