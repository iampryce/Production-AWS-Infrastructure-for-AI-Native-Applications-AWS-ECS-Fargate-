# ADR-006: Decoupled Deploy Strategy — Two Tags, One Force-New-Deployment

## Status

Accepted

## Context

This is the ADR the whole project has been building toward, and the
non-negotiable item CLAUDE.md is most explicit about: Terraform manages
infrastructure *shape* — the ECS cluster, task definitions, services — and
must never own or diff a container image tag. GitHub Actions owns the
*release* — building an image, pushing it, and rolling it out. Getting the
boundary between those two exactly right is the point of this ADR.

## Decision

### Two tags on every push, not one

Every real deploy pushes the same image content under two tags at once:

- An **immutable tag** — the git commit SHA (e.g. `:a1b2c3d`), permanent,
  never overwritten. This is the audit trail: given any SHA, there's
  exactly one image it can refer to, forever.
- A **moving tag** — `:prod` — repointed to that same image on every
  deploy. The ECS task definition's `image` field references `:prod`, and
  only `:prod`, permanently. Terraform sets that reference once (a
  deliberate one-time change, not a per-deploy one — see below) and never
  touches it again.

One tag alone doesn't work: an immutable-only scheme means the task
definition's image reference would have to change on every deploy, which
means Terraform (or something) has to know the current SHA and update
infrastructure state to match — exactly the coupling this whole
architecture exists to avoid. A moving-tag-only scheme works operationally
but throws away the audit trail — you'd have no record of what was
actually running at any point in the past, just whatever `:prod` happens
to point to right now.

### How the rollout actually happens

`.github/workflows/image-build-deploy.yml` (separate from
`terraform-dev.yml`, and it must never touch Terraform state or call
`terraform apply` — same separation of concerns as the plan/apply split):

1. Build the image from `backend/Dockerfile` or `workers/Dockerfile`.
2. Push it tagged with the short git SHA.
3. Push the *same* image tagged `:prod`.
4. Call `aws ecs update-service --force-new-deployment` for the affected
   service.

`force-new-deployment` doesn't register a new task definition revision or
change what image URI the service references — ECS task definitions are
immutable per revision, and the `image` field there has said
`<repo>:prod` since Terraform set it once. What `force-new-deployment`
actually does is tell ECS "start fresh tasks from the current task
definition" — which means re-pulling `:prod`, which now points at new
content. The task definition's shape never changes; only what `:prod`
resolves to does.

### Rollback: re-point `:prod`, don't rebuild

`image-build-deploy.yml` also accepts a `workflow_dispatch` input,
`rollback_sha`. When set, the workflow skips the build step entirely,
pulls the image that's *already* sitting under that SHA tag (pushed by
some earlier deploy), re-tags it `:prod`, pushes that, and calls the same
`force-new-deployment`. Rollback is "point the moving tag at a SHA that
already exists," never a rebuild, and never a Terraform change — it's the
exact same mechanism as a forward deploy, just choosing an older image.

### Deployment history despite the moving tag

The natural worry with a moving tag is losing the ability to answer
"what was running last Tuesday." Two things answer it: the immutable SHA
tags themselves (every image ever deployed is still sitting in ECR under
its own permanent tag, indefinitely, or until the lifecycle policy expires
untagged ones — SHA tags are never untagged, so they're never swept), and
ECS's own deployment history (`aws ecs describe-services` /
`list-tasks` show exactly when each deployment happened). Between the two,
"what was running when" is always answerable without `:prod` itself
carrying any history.

### A dedicated IAM identity for this workflow, not the apply role

Same reasoning as the plan/apply split in ADR-003: this workflow's entire
job is "push an image, restart a service," so its role
(`aws-ai-native-infra-github-actions-deploy`) is scoped to exactly that —
`ecr:*` push actions and `ecs:UpdateService`/`DescribeServices`, both
resource-scoped to this project's own repos/services, nothing else. It
does not carry the apply role's `ec2:*`/`rds:*`/`elasticache:*`/state-
bucket access, because it never needs any of it. Same trust-condition
pattern as the apply role too (`environment:dev` + `ref:refs/heads/main`,
learned the hard way in ADR-003) — tied to the same GitHub Environment
approval gate as infra applies.

### Closing the loop: `use_placeholder_images`

Phases 10/11 (the real FastAPI and Celery code) don't exist yet, so this
phase needed something real to build and push to prove the pipeline
actually works — not just plan cleanly. `backend/Dockerfile` and
`workers/Dockerfile` are minimal placeholders (the same
`python:3.12-slim` + `http.server`/`sleep infinity` behavior already
sitting in the ECS module's Docker-Hub-pulled placeholder, just now
actually built and pushed through the real pipeline instead of pulled
directly). The ECS module's `use_placeholder_images` variable is the one
deliberate switch between "pull a generic image from Docker Hub" and
"reference this module's own ECR repo on `:prod`" — flipping it to `false`
is a one-time Terraform change made *after* this pipeline has pushed
something real to `:prod` for the first time, not before (the ECS service
would fail to pull a tag that doesn't exist yet).

## Consequences

- Two workflows now touch ECS from different angles and must stay that
  way: `terraform-dev.yml` owns shape, `image-build-deploy.yml` owns
  what's running. Neither should ever be tempted to do the other's job.
- Rollback is a real, exercised code path (a `workflow_dispatch` input),
  not just a documented manual procedure.
- `use_placeholder_images` stays `true` until the pipeline has actually
  been run at least once — flipping it before that would break the
  running services by pointing them at a `:prod` tag with nothing behind
  it yet.
