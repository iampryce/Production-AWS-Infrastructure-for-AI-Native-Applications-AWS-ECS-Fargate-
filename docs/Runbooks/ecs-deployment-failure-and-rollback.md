# Runbook: ECS Deployment Failure and Rollback

## Symptom

- `image-build-deploy.yml` (`deploy-fastapi` or `deploy-celery` job)
  completes "successfully" (image built, pushed, `force-new-deployment`
  called), but the new tasks never become healthy — `aws ecs
  describe-services` shows the new deployment stuck `IN_PROGRESS` with
  `runningCount` below `desiredCount`, or tasks starting and immediately
  stopping.
- For FastAPI specifically: `aws-ai-native-infra-dev-alb-unhealthy-hosts`
  alarm fires (Slack).
- Note this workflow rebuilds and redeploys **both** services on any push
  touching `backend/**` or `workers/**` (documented deliberate simplicity
  in the workflow's own header comment) — a failure in one doesn't mean
  the other broke too; check both independently.

## Diagnosis

1. **What actually stopped the task** — the deployment status alone
   won't say why:
   ```powershell
   aws ecs list-tasks --cluster aws-ai-native-infra-dev --service-name aws-ai-native-infra-dev-fastapi --desired-status STOPPED --region us-east-1
   aws ecs describe-tasks --cluster aws-ai-native-infra-dev --tasks <task-arn> --region us-east-1 --query 'tasks[0].{StoppedReason:stoppedReason,Containers:containers[].{Name:name,ExitCode:exitCode,Reason:reason}}'
   ```
   Common `stoppedReason` patterns: `CannotPullContainerError` (bad image
   tag/ECR permissions), a non-zero container exit code (app crashed on
   boot — check logs next), or a failed health check (app started but
   never returned 200 on `/`).

2. **The actual application error** — CloudWatch Logs,
   `/ecs/aws-ai-native-infra-dev-fastapi` or `-celery`, same log group
   names as every other phase's live verification in this project used.
   A migration failure looks different from a missing env var, which
   looks different from an unhandled exception at import time — read the
   actual traceback, don't guess from the ECS-level symptom.

3. **Was it the image, or was it the infra underneath it?** If a
   Terraform change landed in the same window (recall: `terraform-dev.yml`
   and `image-build-deploy.yml` can both fire on the same push with no
   ordering guarantee between them — hit this for real in Phase 11, see
   ADR-012), confirm the task definition revision actually in use has the
   env vars/secrets/IAM the new image expects before assuming the image
   itself is broken.

## Mitigation

**Roll back to the last known-good image** — this is exactly what
`image-build-deploy.yml`'s `workflow_dispatch` + `rollback_sha` input is
for (ADR-006): it re-tags an already-pushed `:sha` image as `:prod`
without rebuilding, then force-deploys.

```
gh workflow run image-build-deploy.yml -f rollback_sha=<short-sha>
```

Find `<short-sha>` from ECR (every real deploy pushes both a `:sha` tag
and the moving `:prod` tag — the SHA tag is the audit trail ADR-006
describes):

```powershell
aws ecr describe-images --repository-name aws-ai-native-infra-dev-fastapi --region us-east-1 --query 'sort_by(imageDetails,& imagePushedAt)[-10:].{Tags:imageTags,Pushed:imagePushedAt}' --output table
```

Pick the last SHA tag that was actually healthy (cross-reference against
`git log` / recent merged PRs, not just "the one before this").

**If the problem is actually infra** (task definition drift, not the
image) — that's a Terraform fix through the normal PR flow
(`terraform-dev.yml`), not something `rollback_sha` can address; rolling
back the image won't help if the task definition itself is wrong.

## Follow-up

- Every rollback here is a live signal that `deployment_circuit_breaker`
  (currently unset — AWS default, disabled, on both services) would have
  caught this automatically. Revisit if manual rollbacks become routine
  rather than rare.
- If the root cause was a bad image that passed CI but failed at
  runtime, consider whether a smoke-test step (hit `/` on the built image
  locally, in the workflow, before pushing `:prod`) would have caught it
  earlier — this project currently has no such gate.
