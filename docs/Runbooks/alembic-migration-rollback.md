# Runbook: Alembic Migration Rollback

## Symptom

- A push to `main` touching `backend/**` deploys, and the FastAPI
  service never reaches steady state — `aws ecs describe-services`
  shows `runningCount` stuck below `desiredCount`, or the ALB's
  `aws-ai-native-infra-dev-alb-unhealthy-hosts` alarm fires.
- The actual cause is a broken migration: `backend/Dockerfile`'s `CMD`
  runs `alembic upgrade head && uvicorn ...` — if `alembic upgrade head`
  fails, the container never starts `uvicorn`, so it never passes the
  ALB health check (`GET /`), and ECS keeps cycling new tasks that all
  fail the same way.
- **Known gap, not a surprise**: `aws_ecs_service.fastapi` doesn't set
  `deployment_circuit_breaker` (`terraform/modules/ecs/services.tf`), so
  ECS does **not** automatically roll back a deployment stuck like this —
  it'll keep retrying the same broken task definition until someone
  intervenes. Worth revisiting if this becomes a recurring problem (see
  Follow-up).

## Diagnosis

1. **Read the actual Alembic error** — CloudWatch Logs,
   `/ecs/aws-ai-native-infra-dev-fastapi`, filter for `alembic`. The
   traceback tells you which revision failed and why (bad SQL, a
   conflicting column, etc.) — don't guess from the deployment symptom
   alone.
2. **Check what's actually applied** — Alembic's own version table
   (`alembic_version` in Postgres) reflects the *last successfully
   applied* revision, which may be one behind what the broken migration
   was trying to reach. Confirm this with `alembic history` locally
   against the same migration chain (`backend/alembic/versions/`) to see
   where the break is relative to what's committed.

## Mitigation

There's no bastion host in this environment and ECS Exec isn't enabled
on these services, so you can't just shell into a running container. The
practical path is a **one-off Fargate task** using the same task
definition, with the command overridden to run Alembic directly instead
of the normal `alembic upgrade head && uvicorn` entrypoint:

```powershell
aws ecs run-task `
  --cluster aws-ai-native-infra-dev `
  --task-definition aws-ai-native-infra-dev-fastapi `
  --launch-type FARGATE `
  --network-configuration "awsvpcConfiguration={subnets=[<app-subnet-id-a>,<app-subnet-id-b>],securityGroups=[<app-sg-id>],assignPublicIp=DISABLED}" `
  --overrides '{"containerOverrides":[{"name":"fastapi","command":["alembic","downgrade","-1"]}]}' `
  --region us-east-1
```

(Subnet/SG IDs: `terraform output` from `terraform/environments/dev`, or
read them off the running service via `aws ecs describe-services`.)

Then either:

- **Roll the schema back** (`alembic downgrade -1`, or a specific
  revision) if the migration itself is wrong and needs to be rewritten,
  or
- **Fix forward** — write a new migration that corrects the problem
  rather than downgrading, if the target schema was actually right but
  the migration had a bug. Fixing forward is usually safer once other
  services may have already observed the partially-applied schema.

Once the schema is in a known-good state, redeploy normally (push a
corrected commit — don't hand-edit anything on the running task; schema
changes only ever go through Alembic, including the fix for this).

## Follow-up

- If this happens more than once, it's worth enabling
  `deployment_circuit_breaker` on the FastAPI service (auto-rollback to
  the last working task definition on repeated failure) rather than
  relying on someone noticing the stuck deployment manually.
- Consider a dedicated migration-runner step in the deploy workflow (run
  `alembic upgrade head` as its own task before the service redeploys,
  so a broken migration fails the *deploy step* loudly instead of
  failing silently inside every new task's boot).
