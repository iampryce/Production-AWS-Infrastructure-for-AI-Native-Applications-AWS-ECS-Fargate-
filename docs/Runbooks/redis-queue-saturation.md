# Runbook: Redis Queue Saturation

## Symptom

One or more of:

- Slack alert: `aws-ai-native-infra-dev-redis-evictions` fired (`Evictions
  > 0` — Redis is dropping keys under memory pressure). This alarm has
  `treat_missing_data = "notBreaching"` and a 1-minute evaluation period,
  so it fires fast and fires on real pressure, not noise.
- Slack alert: `aws-ai-native-infra-dev-redis-cpu-high`
  (`EngineCPUUtilization > 80%` for 3 consecutive minutes).
- User-visible: generation requests stay `pending` far longer than usual
  (Celery isn't draining the queue as fast as FastAPI is filling it), or
  new `POST /generations` calls start timing out because
  `celery_app.send_task()` can't reach the broker.

## Diagnosis

1. **CloudWatch first** — `EngineCPUUtilization`, `Evictions`,
   `DatabaseMemoryUsagePercentage`, and `CurrConnections` for
   `aws-ai-native-infra-dev-redis` (AWS/ElastiCache namespace,
   `ReplicationGroupId` dimension). This tells you whether it's a CPU
   problem (too many operations), a memory problem (too many/too-large
   keys accumulating), or a connection-storm problem.

2. **Flower** (self-hosted, Phase 9, ops subnet — no public route yet,
   see ADR-010's "Consequences": reach it via SSM on the Flower instance
   itself, or once a tunnel ingress route exists, through that) — shows
   actual queue depth (`celery` queue length), active/reserved task
   counts per worker, and whether tasks are failing and retrying
   (`autoretry_for` in `workers/app/tasks.py` means OpenAI rate limits
   specifically will show as repeated retries here, not just a stuck
   queue).

3. **Is it actually queue depth, or is it retries?** A burst of OpenAI
   `RateLimitError`s will make the queue *look* saturated (tasks piling
   up while backing off) without Redis itself being under real pressure.
   Check the celery task's CloudWatch log group
   (`/ecs/aws-ai-native-infra-dev-celery`) for repeated `RateLimitError`
   entries before assuming this is a capacity problem.

## Mitigation

- **If it's genuine queue depth** (worker throughput can't keep up):
  bump `celery_desired_count` in `terraform/environments/dev/terraform.tfvars`
  (ECS module already exposes this) and go through the normal PR flow —
  more workers drain the queue faster. This is safe to do without asking
  first if the alarm is actively firing and the fix is exactly "more of
  what's already there," per this project's incident-response norms;
  document what you did afterward either way.
- **If it's OpenAI rate limits masquerading as queue pressure**: this is
  provider-side, not an infra problem — the existing `retry_backoff` +
  `retry_jitter` already handles it. Confirm the retries are eventually
  succeeding (check for `succeeded` log lines following the retries) and
  consider whether the account's OpenAI rate limit tier needs raising if
  this happens often.
- **If it's a real memory/eviction problem**: `cache.t4g.micro` (the
  current node type, `terraform/modules/redis/variables.tf`) is small by
  design for a dev environment — bump `node_type` via the same PR flow if
  the workload has genuinely outgrown it. Don't `FLUSHALL` as a first
  resort; that's data loss (in-flight job state), only ever a last resort
  with explicit sign-off.
- **Dev-specific reminder**: `automatic_failover_enabled = false` here
  (single node, `terraform.tfvars`) — a Redis-level problem in dev has no
  automatic mitigation the way prod's replica would provide. That's the
  documented cost/resilience tradeoff (ADR-004), not an oversight.

## Follow-up

- If this recurs, revisit `redis_cpu_alarm_threshold`/node sizing rather
  than treating each occurrence as a one-off.
- Confirm the Celery task's `max_retries=3` cap (`workers/app/tasks.py`)
  is still the right number if OpenAI rate limits turn out to be the
  recurring cause — three retries with backoff may not be enough headroom
  under sustained pressure.
