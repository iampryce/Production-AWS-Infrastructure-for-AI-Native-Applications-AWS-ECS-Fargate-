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

**One workflow pair per environment, not dynamic discovery.** An earlier
version of this had a single plan/apply pair that auto-discovered every
`terraform/environments/*` directory and built a matrix from it — technically
slicker, but it hid "which environment does this actually touch" behind a
bash/jq script, which is the wrong thing to optimize away on a project meant
to be read and explained. `terraform-dev-plan.yml` and
`terraform-dev-apply.yml` are hardcoded to `dev`, full stop. When
staging/prod exist, they get their own copy-pasted pair
(`terraform-staging-plan.yml`, etc.) rather than folding into shared
discovery logic. Each apply workflow is tied to a GitHub Environment of the
same name (`environment: dev`) — required-reviewer protection rules can be
added per environment later as a plain repo setting, giving prod a manual
approval gate without any code change.

## Consequences

- From this point on, nobody runs `terraform apply` from a laptop — every
  real change goes through a PR, gets a plan comment, and applies only
  after merge to `main`.
- The apply role's policy is a living document — it grows one phase at a
  time, in the same commit that introduces the module needing the new
  permission, so the IAM policy and the infrastructure it's permitting stay
  honest with each other.
- The bootstrap module (`terraform/bootstrap/`) itself is still applied by
  hand, deliberately — it's what creates the very roles CI/CD depends on,
  so it can't bootstrap itself through CI/CD it doesn't have yet.
