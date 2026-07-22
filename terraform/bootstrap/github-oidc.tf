

variable "github_repo" {
  description = "owner/repo, must match the OIDC trust condition exactly."
  type        = string
  default     = "iampryce/Production-AWS-Infrastructure-for-AI-Native-Applications-AWS-ECS-Fargate-"
}

locals {
  github_owner     = split("/", var.github_repo)[0]
  github_repo_name = split("/", var.github_repo)[1]
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

    # Wildcarded after each name segment for the same reason as the apply
    # role below — matches whether or not GitHub embeds a numeric
    # owner/repo ID after the name, without ever matching another repo.
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${local.github_owner}*/${local.github_repo_name}*:*"]
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

    # AWS requires this provider's trust policy to evaluate `sub` (or
    # job_workflow_ref), scoped and non-wildcarded — a policy built only
    # from other claims like `environment`/`ref` gets rejected outright
    # ("MalformedPolicyDocument ... must evaluate ... sub ... which is not
    # scoped to all"), discovered the hard way on the first real apply.
    #
    # GitHub's OIDC token changes `sub`'s format to
    # "repo:OWNER/REPO:environment:NAME" the moment a job sets
    # `environment:` (as the apply job does) — but the actual value
    # observed via CloudTrail on this account is
    # "repo:iampryce@170509563/REPO-NAME@1307826954:environment:dev", with
    # GitHub's own stable numeric owner/repo IDs embedded after each name
    # (protects the trust policy from breaking on a repo rename/transfer —
    # not something this policy controls or should hardcode). StringLike
    # with wildcards in exactly those two spots matches real tokens for
    # this repo regardless of the numeric ID, without falling back to
    # matching "all" the way a bare `*` would — GitHub, not the token
    # requester, controls what can appear after `@`, so this stays scoped
    # to this specific repo.
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${local.github_owner}*/${local.github_repo_name}*:environment:dev"]
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

# Scoped to what Phases 0-3 actually need (networking + RDS + ElastiCache).
# Expand this policy phase by phase as new modules land (ECS/ECR,
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
    sid = "ElastiCache"
    actions = [
      "elasticache:*",
    ]
    resources = ["*"]
  }

  statement {
    sid = "ECSPhase4"
    actions = [
      "ecs:*",
      "ecr:*",
      "elasticloadbalancing:*",
      "application-autoscaling:*",
      "logs:*",
    ]
    resources = ["*"]
  }

  # Route 53 hosted zone IDs and ACM certificate ARNs aren't known ahead
  # of applying this same change (the zone/cert are created by it), so
  # scoping tighter than the account would mean a circular reference from
  # this separate bootstrap state - same reasoning as ec2:*/rds:* above.
  statement {
    sid = "EdgeAndDnsPhase6"
    actions = [
      "route53:*",
      "acm:*",
      "cloudfront:*",
      "wafv2:*",
    ]
    resources = ["*"]
  }

  # New assets bucket from the cloudfront module - separate statement from
  # TerraformStateBucket below since that one is scoped to exactly one
  # bucket ARN and shouldn't grow implicitly as more project buckets show
  # up. Prefix-scoped to this project's buckets only, not every bucket in
  # the account.
  #
  # Read side is Get*/List* broadly rather than enumerated action-by-
  # action: aws_s3_bucket reads back many sub-attributes on every refresh
  # (ACL, versioning, CORS, logging, replication, etc.), discovered via a
  # real AccessDenied on s3:GetBucketAcl that wasn't in the original list
  # - enumerating each one individually is a whack-a-mole this project
  # isn't interested in playing twice. Write side stays explicit, since
  # those are the actions that actually mutate state.
  statement {
    sid = "S3ForProjectBuckets"
    actions = [
      "s3:CreateBucket",
      "s3:DeleteBucket",
      "s3:PutBucketPolicy",
      "s3:DeleteBucketPolicy",
      "s3:PutBucketPublicAccessBlock",
      "s3:PutEncryptionConfiguration",
      "s3:PutBucketTagging",
      "s3:Get*",
      "s3:List*",
    ]
    resources = [
      "arn:aws:s3:::${var.project_name}-*",
    ]
  }

  # RDS needs the calling principal (this role) to have KMS grant
  # permissions to use a KMS key on its behalf - including the AWS-managed
  # defaults (aws/rds for storage_encrypted, aws/secretsmanager for the
  # RDS-managed master password). Discovered via a real
  # KMSKeyNotAccessibleFault on the first live apply. Resource "*" because
  # AWS-managed key ARNs aren't known ahead of time and aren't created by
  # this Terraform config.
  statement {
    sid = "KMSForManagedKeys"
    actions = [
      "kms:DescribeKey",
      "kms:CreateGrant",
      "kms:ListGrants",
      "kms:RetireGrant",
    ]
    resources = ["*"]
  }

  # Covers two distinct secrets: RDS's manage_master_user_password = true
  # (RDS creates and owns the secret, but the calling principal still
  # needs permission for RDS to do that creation on its behalf - not just
  # read it afterward, discovered via a real AccessDenied on the first
  # live apply: "The user isn't authorized to create a secret in AWS
  # Secrets Manager") and the redis module's own Secrets Manager secret
  # for its AUTH token (ElastiCache has no equivalent managed-password
  # feature, so the module creates the secret itself and needs the same
  # write actions).
  statement {
    sid = "SecretsManagerForManagedSecrets"
    actions = [
      "secretsmanager:CreateSecret",
      "secretsmanager:DeleteSecret",
      "secretsmanager:TagResource",
      "secretsmanager:PutSecretValue",
      "secretsmanager:GetSecretValue",
      "secretsmanager:GetResourcePolicy",
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

# --- Deploy role: pushes images and rolls ECS services, main branch only ---
#
# Deliberately separate from the apply role, same reasoning as the
# plan/apply split in ADR-003: this identity's whole job is "push an image,
# restart a service" (Phase 5's image-build-deploy.yml), and it has no
# reason to carry the apply role's ec2:*/rds:*/elasticache:*/state-bucket
# access just to do that. Different blast radius, different role.

data "aws_iam_policy_document" "github_deploy_trust" {
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

    # Same environment:dev + ref:refs/heads/main pattern as the apply role
    # (ADR-003) - ties image deploys to the same GitHub Environment
    # approval gate as infra applies, and to main only.
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${local.github_owner}*/${local.github_repo_name}*:environment:dev"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:ref"
      values   = ["refs/heads/main"]
    }
  }
}

resource "aws_iam_role" "github_deploy" {
  name               = "${var.project_name}-github-actions-deploy"
  assume_role_policy = data.aws_iam_policy_document.github_deploy_trust.json
}

data "aws_iam_policy_document" "github_deploy_permissions" {
  # ECR authentication (docker login) has no resource-level scoping in
  # IAM - GetAuthorizationToken always requires Resource "*".
  statement {
    sid       = "EcrAuth"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  # Scoped to this project's repos only, not every ECR repo in the account.
  statement {
    sid = "EcrPush"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:PutImage",
    ]
    resources = [
      "arn:aws:ecr:*:*:repository/${var.project_name}-*",
    ]
  }

  # Scoped to this project's ECS services only.
  statement {
    sid = "EcsForceDeploy"
    actions = [
      "ecs:UpdateService",
      "ecs:DescribeServices",
    ]
    resources = [
      "arn:aws:ecs:*:*:service/${var.project_name}-*/${var.project_name}-*",
    ]
  }

  statement {
    sid       = "STSIdentity"
    actions   = ["sts:GetCallerIdentity"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "github_deploy_permissions" {
  name   = "${var.project_name}-github-actions-deploy-permissions"
  role   = aws_iam_role.github_deploy.id
  policy = data.aws_iam_policy_document.github_deploy_permissions.json
}
