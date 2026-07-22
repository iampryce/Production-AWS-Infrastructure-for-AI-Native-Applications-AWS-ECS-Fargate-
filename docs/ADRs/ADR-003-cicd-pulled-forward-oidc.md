# ADR-003: CI/CD Pulled Forward, OIDC Instead of Long-Lived Keys

## Status

Accepted

## Context

Early on, every `terraform plan` had been run from a local terminal, with
`apply` left for me to run by hand after reviewing the plan. That's fine
for a couple of modules, but it doesn't scale, and more importantly it
isn't the story this project is supposed to tell — a proper Terraform
GitOps pair (`plan` on PR, `apply` on merge to `main`) was always the
intended end state, it just hadn't been built yet. Once real infra started
existing, it stopped making sense to keep applying locally for several
more modules and only then switch — so the CI/CD piece got pulled forward
much earlier than originally planned.

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
land, not granted speculatively now.

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

**Incident: the trust condition was wrong on the first real run — twice.**
The `apply` role's trust condition originally matched
`sub = "repo:${var.github_repo}:ref:refs/heads/main"`. The first push to
`main` failed at `configure-aws-credentials` with `Not authorized to
perform sts:AssumeRoleWithWebIdentity`. CloudTrail
(`aws cloudtrail lookup-events --lookup-attributes
AttributeKey=EventName,AttributeValue=AssumeRoleWithWebIdentity`) showed
the actual token presented had `sub = "repo:.../REPO:environment:dev"`,
not the `ref:refs/heads/main` form expected. Cause: GitHub changes the
`sub` claim's format the moment a job sets `environment:` (which `apply`
does, for the approval-gate feature) — it becomes `environment:<name>`
instead of `ref:refs/heads/<branch>`, unconditionally.

First attempt at a fix dropped `sub` entirely in favor of matching the
`environment` and `ref` claims directly. That failed too, but this time at
`terraform apply` itself, not at runtime: AWS rejects any trust policy for
this OIDC provider that doesn't evaluate `sub` (or `job_workflow_ref`) as
a scoped, non-wildcarded condition —
`MalformedPolicyDocument: ... must evaluate ... sub ... which is not
scoped to all`. AWS specifically requires anchoring to one of those two
claims; other claims alone aren't sufficient, however precisely scoped.

Second fix: keep `sub`, using the value CloudTrail showed
(`repo:${var.github_repo}:environment:dev`), plus `ref` as a second, ANDed
condition. That satisfied AWS's validation and applied cleanly — but the
*next* real run still failed with the exact same runtime `AccessDenied`.
Looking at CloudTrail again, the actual `sub` presented was
`repo:iampryce@170509563/Production-AWS-Infrastructure-for-AI-Native-
Applications-AWS-ECS-Fargate-@1307826954:environment:dev` — GitHub embeds
its own stable numeric owner/repo IDs directly into the subject
(protection against a repo rename/transfer silently invalidating trust
policies elsewhere), not just `owner/repo` names the way the commonly
documented example format shows. Third and final fix: `StringLike` with a
wildcard placed right after each name segment
(`repo:iampryce*/REPO-NAME*:environment:dev`) — matches the real token
regardless of the numeric ID, without matching any other repo, since
GitHub (not the token requester) controls what can legally appear after
`@`. Applied the same wildcard defensively to the `plan` role's condition
too, even though it hadn't been exercised by a real PR yet.

Three real bugs in one afternoon, three different failure modes (silent
runtime `AccessDenied`, a `terraform apply`-time policy validation error,
then a second silent runtime `AccessDenied` from an unexpectedly-shaped
claim) — the throughline: don't assume an OIDC claim format from
documentation or a first success, verify it against what's actually being
presented (CloudTrail, in this case), especially once a job introduces a
new feature like `environment:` that changes claim shape in ways that
aren't obvious from the workflow YAML alone.

## Addendum: the plan role can't refresh secret content, on purpose

Discovered on the first PR that actually got its `plan` job reviewed
carefully end to end: `terraform plan`'s default state refresh
tries to re-read every `aws_secretsmanager_secret_version` resource's
actual value (RDS's, Redis's, and later the Cloudflare tunnel's), which
needs `secretsmanager:GetSecretValue` — a permission `ReadOnlyAccess`
excludes on purpose (AWS's own managed policy treats secret payloads
differently from read-only metadata). The `plan` role can't be given that
permission: it's assumable from **any branch or PR** by design, specifically
so a compromised or careless PR workflow can only ever read, never mutate.
Granting `GetSecretValue` would mean any PR author could read live
production credentials directly — a materially bigger hole than the
"read-only" guarantee this whole role split exists to provide.

Fix: `terraform plan` in the `plan` job runs with `-refresh=false`
(`.github/workflows/terraform-dev.yml`) — it diffs the `.tf` config against
the last-known state from the most recent `apply`, not a live re-read of
AWS. The `apply` job is unaffected; it still does a full refresh before
applying, using the write-capable role that already has
`secretsmanager:GetSecretValue` for its own reasons. Tradeoff: the PR-time
plan won't catch out-of-band drift (e.g. someone hand-editing a resource in
the AWS console) between applies — acceptable, since catching that isn't
what the PR plan step is for; it's for previewing the change this PR is
about to make.

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
