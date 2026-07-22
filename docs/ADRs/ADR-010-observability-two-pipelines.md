# ADR-010: Observability — Two Independent Pipelines, Built as Designed

## Status

Accepted

## Context

CLAUDE.md items 11-13 already settle the shape of this: an app-level
pipeline (OpenTelemetry -> a self-hosted collector -> Grafana Cloud +
Jaeger, with Sentry and LangSmith bypassing the collector via their own
SDKs) and a completely separate infra-level pipeline (CloudWatch -> SNS ->
Lambda -> Slack, the one alerting channel). The real work here was making
both real and live, not deciding the shape.

## Decision

### Infra-level pipeline: CloudWatch -> SNS -> Lambda -> Slack

Nine alarms across ECS (FastAPI/Celery CPU + memory), ALB (target 5xx
count, unhealthy host count), RDS (CPU, free storage), and Redis (engine
CPU, evictions) - all pointed at one SNS topic. Evictions specifically
(not just a CPU/memory threshold) because it's a direct, early signal for
the "redis-queue-saturation" runbook Phase 13 will write, not just generic
resource pressure.

The Lambda notifier is plain Python stdlib (`urllib.request`, `boto3`
which ships with the runtime) - no dependency layer to build or maintain
for what's fundamentally "format a message, POST it." It fetches the
Slack webhook URL from Secrets Manager at invoke time rather than a plain
Lambda environment variable holding the value directly, scoped IAM to
exactly that one secret ARN.

### Both external credentials flow in via TF_VAR_, never tfvars, never a manual AWS CLI step

Earlier phases (Cloudflare Tunnel, ADR-008) settled on "data source reads
a secret you create by hand" for values with no Terraform provider path.
This phase does it differently, on request: the Slack webhook URL and the
Grafana Cloud API key both flow in as `TF_VAR_slack_webhook_url` /
`TF_VAR_grafana_cloud_api_key` env vars in `terraform-dev.yml`, sourced
from GitHub Actions secrets, and Terraform creates the Secrets Manager
entries itself (same shape as the Redis module's AUTH token). The
distinction that matters: this isn't Terraform automating the external
side (nobody's teaching Terraform to create a Slack webhook or a Grafana
API key) - it's just skipping a manual `aws secretsmanager create-secret`
hop that added nothing except a step to forget. Both variables are marked
`sensitive = true` and have no entry in `terraform.tfvars`, which is
committed to git. The two non-secret Grafana values (OTLP endpoint,
instance ID) *do* live in `terraform.tfvars` - they identify an
ingestion target, not a credential.

### One EC2, two containers: the OTel Collector and self-hosted Jaeger

Jaeger isn't named in CLAUDE.md's ops-subnet content list the way
Flagsmith/OTel-collector/Flower are - decided (asked first) to self-host
it anyway, all-in-one image, sharing a Docker network with the collector
on the same instance rather than a second EC2. Traces go to both Jaeger
(a dedicated UI reachable without any Grafana Cloud credentials at all -
useful for a demo where someone might not have Grafana open) and Grafana
Cloud's OTLP gateway (so dashboards can correlate traces with metrics,
which only go to Grafana Cloud - Jaeger doesn't do metrics). Config is a
real YAML file, not a stub - rendered once by Terraform (endpoint URL,
the one value known at apply time) and finished by the boot script at
runtime (the Grafana Cloud auth header, base64 of
`instance_id:api_key`, computed from a Secrets Manager value Terraform
never touches).

### Flower gets its own EC2, and the one deliberate Data-SG exception

Flower has to reach the exact broker Celery uses - there's no version of
"Celery queue monitoring" that doesn't need that. CLAUDE.md item 3 says
Data SG allows App tier only, "not even ops," explicitly - flagged this
conflict before writing any networking code, and the resolution (asked
first, not assumed): one narrow new ingress rule on the existing `data`
SG, Redis port only, Ops SG only. Postgres stays completely untouched -
App tier only, no exception, no reason for one.

### Sentry/LangSmith: deferred, not skipped

Both need FastAPI/Celery source files to instrument - which don't exist
until Phases 10/11. Building Terraform for either now would mean guessing
at code that doesn't exist yet, the same "don't build ahead of the phase
that needs it" discipline this project already applies elsewhere (ECS's
placeholder images, the empty task-role policies in Phase 4). Nothing in
this phase blocks on it.

## Two real bugs, both found via genuine live verification, both fixed on the second pass

Every phase this project has actually pushed through CI has hit at least
one first-apply surprise (ADR-004's service-linked role, ADR-007's IAM
growth, ADR-008's cloudflared repo URL, ADR-009's SG-description
apostrophe and undersized root volume). This phase is no exception, and
both were caught the same way those were - reading `aws ec2
get-console-output` rather than trusting a clean `terraform apply` to
mean the application layer is healthy:

1. **Flower crash-looped.** The Redis module's `random_password` charset
   (`!#$%^&*()-_=+[]{}<>:?`) is correctly scoped to what ElastiCache's own
   AUTH token restricts (no `/`, `"`, `@`) - but nobody had asked whether
   that same token would ever need to live inside a URL, where `:` is a
   reserved separator. It does now (Flower's `rediss://:TOKEN@host:port/0`
   broker string), and a token containing a literal `:` breaks that
   parse. Confirmed via the console log's repeated veth-interface
   create/teardown cycles at growing intervals - Docker's own backoff
   pattern for a `--restart unless-stopped` container that keeps exiting -
   and the literal malformed URL sitting in the boot script's own command
   line. Fixed by percent-encoding the token immediately before it goes
   into the URL (`python3 -c 'import urllib.parse...'`, already present
   via cloud-init's own dependencies - no new package needed), not by
   changing the token's charset, which is correctly scoped to a different
   requirement (ElastiCache's, not URL-encoding's).

   **Forward note for Phase 11**: ECS's task definitions pass
   `REDIS_HOST`/`REDIS_PORT`/`REDIS_AUTH_SECRET` as separate values, not a
   pre-built URL, so Celery itself was never exposed to this - but
   whatever Celery/kombu broker-URL construction Phase 11 writes needs the
   same percent-encoding, for the same reason. Noted here so it's not
   rediscovered the hard way a second time.

2. **A backtick in a YAML comment nearly did something worse than
   cosmetic damage.** `otel-collector-config.yaml.tpl` had a comment
   reading "...not by `terraform apply`." - ordinary markdown-style
   code-formatting habit, except that file's rendered text gets spliced
   into an *unquoted* heredoc in `otel_user_data.sh.tpl`
   (`cat > config.yaml <<EOF ... EOF`), and bash treats backticks as
   legacy command substitution even inside what reads as a YAML comment
   to a human. The boot script actually attempted to execute
   `terraform apply` as a shell command mid-heredoc. Harmless this time
   (`terraform: command not found` on an instance that has no reason to
   have Terraform installed, and command-substitution failures inside a
   heredoc don't trip `set -e` the way a top-level command's failure
   would) - but the exact kind of thing that wouldn't stay harmless on a
   different instance or a differently-worded comment. Fixed by removing
   the backticks and documenting, directly in that file, why none belong
   there at all.

## Consequences

- Bootstrap's apply-role policy grew again, in the same commit that
  introduces this module (`cloudwatch:*`, `sns:*`, `lambda:*`) - applied
  by hand, planned and reviewed first, same as every bootstrap change.
- **Verified live, thoroughly**: the CloudWatch -> SNS -> Lambda -> Slack
  path is confirmed working with a real message received in Slack (not
  just "the alarm exists"). The OTel Collector, Jaeger, and Flower all
  came up clean on the second attempt, confirmed via console-output
  inspection, not assumed from a clean `terraform apply`.
- Not yet verified, and out of scope for this phase specifically: whether
  traces/metrics are actually flowing correctly end-to-end into Grafana
  Cloud or Jaeger's UI, since nothing in this project emits OTLP data yet
  (that starts in Phases 10/11) - the collector is confirmed *running*,
  not confirmed *receiving real telemetry*.
- Neither Jaeger's UI nor Flower's UI is reachable from outside the VPC
  yet - no public IP (by design) and no Cloudflare Tunnel ingress route
  configured to proxy into either one. Same gap already noted in
  ADR-008/ADR-009 for Flagsmith's admin UI; a real fix here is wiring
  actual tunnel ingress rules, which is Phase 7 follow-up work, not
  something to solve piecemeal per service as each one lands.
