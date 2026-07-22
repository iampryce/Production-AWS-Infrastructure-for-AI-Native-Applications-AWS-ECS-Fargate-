# ADR-012: Celery Worker — Consume, Generate, Store, Update

## Status

Accepted

## Context

BUILD_PLAN's Phase 11: consume the queue Phase 10 already proved works,
call the AI provider, store the result in S3, update job status in
Postgres. Handle rate limits and provider errors with retry/backoff -
don't crash the worker. This phase is where the `generate_content` task
name/contract established in Phase 10 (ADR-011) finally gets a real
implementation on the consuming side.

## Decision

### OpenAI, text only, for now

Three real decisions with cost/scope implications, asked rather than
assumed: OpenAI over Gemini/OpenRouter (most common choice, easiest to
explain), a personalized text message only rather than also generating an
image (image generation is a real scope and cost addition deserving its
own explicit decision later, not something to fold in silently), and the
existing Phase 6 assets bucket rather than a new one (already has
CloudFront OAC wired up - reusing it is less new surface, not more).

### Retry only what's actually retryable

`autoretry_for` is scoped to OpenAI's own transient failure modes
(`RateLimitError`, `APIConnectionError`, `APITimeoutError`,
`InternalServerError`) with backoff and jitter, capped at 3 attempts -
not a bare `except Exception`. A bug in this code (a missing env var, a
typo) should fail loudly and immediately, not retry three times against
an error retrying can never fix. This is the literal reading of "handle
rate limits and provider errors with retry/backoff," not "retry
everything."

### `status = "failed"` only on genuine final failure

A custom `Task.on_failure` hook, not a bare `except` in the task body -
Celery only calls `on_failure` once retries are truly exhausted, so a
request that succeeds on its second attempt never gets marked failed
first and then silently overwritten back to completed. Matters for
anyone actually watching this status transition (a future frontend,
Flower) - "failed" should mean failed, not "failed on attempt one."

### Two real bugs, both found via genuine live verification

**The celery/terraform push-order race actually happened, and resolved
itself.** This commit touched both `terraform/**` and `workers/**`,
triggering `terraform-dev.yml` (new task definition revision, S3/OpenAI
IAM) and `image-build-deploy.yml` (real worker image) on the same push,
with no ordering guarantee between the two separate workflow files.
Checked afterward rather than assumed: both completed cleanly, the new
task definition (revision 3) was live with the new image. Worth hardening
later with a `workflow_run` trigger so `image-build-deploy` only fires
after `terraform-dev`'s apply succeeds - not done now since it worked and
this project fixes what's actually broken over what might theoretically
race, but noted here so it isn't forgotten.

**The `assets/` key prefix was missing from the actual S3 write, only
present in the URL construction.** CloudFront's `/assets/*` cache
behavior (Phase 6) has no `origin_path` rewrite, so a public URL like
`<site>/assets/generations/<id>.json` maps directly to S3 key
`assets/generations/<id>.json` - the worker's `s3.put_object()` call used
`generations/<id>.json`, one segment short, while the `result_url` string
was built as if the prefix were there. This produced a working-looking
API response (`status: completed`, a `result_url` that looked correct)
that 403'd at the actual CloudFront edge - the kind of bug a
plan/apply-only check, or even a "does the API return 200" check, would
never catch. Only caught by actually curling the real public URL, per
this project's standing discipline of checking the thing a user would
actually hit, not just the layer directly in front of the code change.
Fixed by moving the `assets/` prefix into the S3 key itself (the single
source of truth) and redefining `PUBLIC_ASSET_BASE_URL` as the site root
rather than "already includes /assets," so the two can never drift apart
silently again. The one orphaned object under the old, wrong key was
deleted rather than left as dead weight.

## Consequences

- No apply-role IAM changes were needed beyond what Phase 9 already
  granted (`ec2:*`/IAM/Secrets Manager already covered this).
- **Verified live, twice - locally and in real AWS, and re-verified after
  the fix.** Locally: real OpenAI call, real object in a local MinIO
  S3-compatible store, correct DB transition. In AWS, first pass:
  everything worked *except* the public URL, caught and fixed. Second
  pass: a fresh request through the live ALB produced a `completed`
  status whose `result_url` returns a real HTTP 200 with the actual
  generated message, through the actual CloudFront distribution.
  Additionally, closed the loop on a request submitted back in Phase 10 -
  it sat in the queue with no consumer until this worker deployed, then
  got picked up and processed automatically, no manual intervention.
- Sentry/LangSmith instrumentation (CLAUDE.md item 11) still isn't wired
  into this code - real follow-up work, not blocking either backend or
  worker phase.
- Image generation, if ever added, is a distinct future decision with its
  own cost/scope conversation - not something this phase's "text only"
  choice quietly forecloses.
