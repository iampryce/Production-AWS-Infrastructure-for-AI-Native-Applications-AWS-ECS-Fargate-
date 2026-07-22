# ADR-003: CI/CD Pulled Forward, OIDC Instead of Long-Lived Keys

## Status

Accepted

## Context

Up through Phase 2, every `terraform plan` had been run from a local
terminal, with `apply` left for me to run by hand after reviewing the
plan. That's fine for a couple of modules, but it doesn't scale, and more
importantly it isn't the story this project is supposed to tell — the
original plan (Phase 5) already called for a proper Terraform GitOps pair
(`plan` on PR, `apply` on merge to `main`), it just hadn't been built yet.
Once real infra started existing, it stopped making sense to keep applying
locally for three more phases and only then switch — so the CI/CD piece
got pulled forward to right after Phase 2, ahead of the original schedule.

## Decision

**No AWS access keys stored anywhere, ever.** GitHub Actions authenticates
to AWS via **OIDC** (OpenID Connect) — GitHub issues a short-lived signed
token per workflow run, AWS trusts it directly through an identity
provider, and the workflow assumes an IAM role for the duration of the job.
No `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` pair sitting in GitHub
secrets waiting to leak or need rotation.

**The OIDC provider is reused, not recreated.** AWS only allows one
`token.actions.githubusercontent.com` provider per account, and this
account already had one from an earlier project. Recreating it would have
just failed — reusing it via a data source and building new,
project-scoped IAM roles on top is the correct move, not a compromise.

**Two IAM roles, not one — split by what triggers them:**
- `aws-ai-native-infra-github-actions-plan`: `ReadOnlyAccess`, and its OIDC
  trust condition allows it from **any branch or PR** of this repo. It
  physically cannot create, modify, or delete anything — even a
  compromised or badly-written PR workflow can only ever read.
- `aws-ai-native-infra-github-actions-apply`: has real write permissions,
  but its trust condition restricts `sub` to
  `repo:iampryce/<repo>:ref:refs/heads/main` specifically. It cannot be
  assumed from a PR branch, a fork, or anywhere else — only a push to
  `main` (i.e., a merged, reviewed PR) can trigger it.

This means the **plan visible in a PR is the actual confirmation step** —
merging is the explicit approval to apply, which is the same "show me the
plan, get explicit confirmation" rule this project already holds itself to
locally, just enforced by branch protection instead of a person running
commands by hand.

**The apply role's permissions are scoped to what exists today, not what
might exist later.** It currently covers EC2 (networking), RDS,
Secrets Manager reads (for the RDS-managed master password), IAM limited
to this project's own naming prefix (`aws-ai-native-infra-*` roles/instance
profiles only — it cannot touch IAM entities outside that prefix), and
this project's own state bucket. ElastiCache, ECS, CloudFront, Route 53,
ACM, Lambda, and SNS permissions get added when those modules actually
land in Phases 3+, not granted speculatively now.

**One workflow file per environment, not dynamic discovery.** An earlier
version of this had a single plan/apply pair that auto-discovered every
`terraform/environments/*` directory and built a matrix from it — technically
slicker, but it hid "which environment does this actually touch" behind a
bash/jq script, which is the wrong thing to optimize away on a project meant
to be read and explained. `terraform-dev.yml` is hardcoded to `dev`, full
stop. It briefly existed as two separate files (`terraform-dev-plan.yml` /
`terraform-dev-apply.yml`) before being folded back into one file with two
jobs — `plan` gated to `pull_request` events, `apply` gated to `push`
events — since one file is easier to open and read top to bottom, and the
job split (not a file split) is what actually carries the security-relevant
distinction between the two IAM roles. When staging/prod exist, they get
their own copy-pasted `terraform-staging.yml` / `terraform-prod.yml` rather
than folding into shared discovery logic. The apply job is tied to a GitHub
Environment of the same name (`environment: dev`) — required-reviewer
protection rules can be added per environment later as a plain repo
setting, giving prod a manual approval gate without any code change.

**No PR-comment bot for the plan output.** The `plan` job also briefly
posted the plan as a PR comment via an embedded `actions/github-script`
block (~25 lines of JS-in-YAML). Dropped it — `terraform plan` already
writes its full output to the job's Actions log regardless, so the comment
step bought a small UX convenience (seeing the diff inline in the PR
instead of one click into Checks) at the cost of being the least
standard-looking, hardest-to-explain part of the whole file. Removing it
also removed the reason for `continue-on-error: true` and a manual
"fail the job if plan failed" step, since `terraform plan` is now allowed
to fail the job naturally like any other step. Net: five fewer moving
parts for one click of convenience — worth it on a project meant to be
read line by line.

**Incident: the trust condition was wrong on the first real run.** The
`apply` role's trust condition originally matched
`sub = "repo:${var.github_repo}:ref:refs/heads/main"`. The very first push
to `main` failed at `configure-aws-credentials` with
`Not authorized to perform sts:AssumeRoleWithWebIdentity`. CloudTrail
(`aws cloudtrail lookup-events --lookup-attributes
AttributeKey=EventName,AttributeValue=AssumeRoleWithWebIdentity`) showed
the actual token presented had `sub = "repo:.../REPO:environment:dev"`,
not the `ref:refs/heads/main` form the trust policy expected. The cause:
GitHub changes the `sub` claim's format the moment a job sets
`environment:` (which the `apply` job does, for the approval-gate
feature) — it becomes `environment:<name>` instead of
`ref:refs/heads/<branch>`, unconditionally. The fix isn't to chase that
composite string — GitHub's OIDC token carries `environment` and `ref` as
independent claims alongside `sub`, so the trust policy now checks both
directly (`token.actions.githubusercontent.com:environment = "dev"` AND
`:ref = "refs/heads/main"`), which is more precise than parsing one
composite value ever was.

## Consequences

- From this point on, nobody runs `terraform apply` from a laptop — every
  real change goes through a PR, gets planned in the `plan` job (visible in
  that PR's Actions log — no PR-comment bot, kept deliberately simple), and
  applies only after merge to `main`.
- The apply role's policy is a living document — it grows one phase at a
  time, in the same commit that introduces the module needing the new
  permission, so the IAM policy and the infrastructure it's permitting stay
  honest with each other.
- The bootstrap module (`terraform/bootstrap/`) itself is still applied by
  hand, deliberately — it's what creates the very roles CI/CD depends on,
  so it can't bootstrap itself through CI/CD it doesn't have yet.
