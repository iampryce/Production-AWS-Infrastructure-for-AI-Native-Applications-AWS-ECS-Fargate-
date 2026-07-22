# ADR-009: Self-Hosted Flagsmith — EC2 + Its Own Small RDS Instance

## Status

Accepted

## Context

CLAUDE.md item 15 calls for self-hosted Flagsmith (feature flags) on its
own EC2 instance plus its own small RDS instance, in the ops subnet,
reachable internally by FastAPI/Celery and never exposed publicly. The one
real design question was how literally to take "in the ops subnet" for the
RDS half specifically.

## Decision

### The RDS instance lives in the data subnets, not literally the ops subnet

RDS requires a DB subnet group spanning **at least two subnets in two
different AZs** — the ops subnet is deliberately single-AZ (ADR-001), so a
standalone subnet group built only from it isn't possible. Flagsmith's
Postgres instance uses the existing `data-a`/`data-b` subnets instead,
matching where every other database in this project already lives. What
actually satisfies "in the ops subnet" is the **Flagsmith EC2 instance
itself** — that's the literal Flagsmith service CLAUDE.md is describing,
and it's genuinely there with no public IP, no key pair, SSM for direct
troubleshooting, same as every other ops-subnet instance in this project.

This isn't just a subnet-group technicality worth glossing over: putting
the DB in the data subnets, unguarded, would put it one misconfigured rule
away from being reachable by the main app's data tier too. So it gets its
own **dedicated security group** (`flagsmith-db-sg`), not the shared `data`
SG — ingress restricted to Postgres from the **ops SG only**. The shared
`data` SG's "App tier only" rule (CLAUDE.md item 3) stays untouched and
unambiguous; nothing about Flagsmith's database is reachable from FastAPI
or Celery directly, which is correct, since they're not supposed to talk to
it at all — only the Flagsmith EC2 instance itself does. Confirmed this
before writing any code (asked first, since it's a deviation from the
literal subnet plan) rather than assuming and finding out later.

### Reachability: App → Flagsmith's HTTP API, not App → Flagsmith's database

The network module already had this half-anticipated from Phase 1 —
`ops_flagsmith_from_app` (App SG → Ops SG on `flagsmith_port`, default
`8000`) and a `flagsmith_port` variable both existed, unused, before this
phase. FastAPI/Celery reach Flagsmith's HTTP API over that existing rule;
nothing new was needed on the network module's side.

### All-in-one Docker image, not separate containers

Flagsmith ships `flagsmith/flagsmith:latest` as a single image bundling
the Django API and its built React frontend — one container, `docker run
-d --restart unless-stopped`, rather than orchestrating multiple
containers or writing a Compose file for a single EC2 instance. `dnf
install docker` (AL2023's own package, not Docker's upstream repo) plus
`systemctl enable --now docker` in `user_data`, mirroring the Cloudflare
Tunnel module's boot-script shape from Phase 7.

### Two secrets, two different lifecycles

The RDS master password uses `manage_master_user_password = true` — same
as the main app's RDS module, AWS creates and owns that secret natively,
never touching Terraform state. The Django secret key has no AWS-managed
equivalent, so this module generates one itself
(`random_password` + `aws_secretsmanager_secret`), same pattern as the
Redis module's AUTH token and the Cloudflare Tunnel's connector token —
without a stable key, every container restart would invalidate all
sessions. The boot script fetches both via the instance's scoped IAM role
(`secretsmanager:GetSecretValue` on exactly these two ARNs) rather than
either value ever appearing in `user_data` as a literal value, same
reasoning as the Cloudflare Tunnel module.

### Always single-AZ, deliberately, even in prod

Unlike the main RDS/Redis modules, there's no `multi_az` variable here at
all — hardcoded `multi_az = false`. Feature flags aren't on the critical
request path the way the primary database is; losing Flagsmith briefly
during an AZ event is a real but acceptable gap for this project's scope,
not worth doubling a second database's cost to close.

## Three real bugs on the first live attempts

This phase needed three apply cycles before Flagsmith actually came up —
worth recording honestly, same as ADR-004/ADR-007/ADR-008's own first-apply
findings:

1. **SG description charset, again.** `aws_security_group.flagsmith_db`'s
   description used an apostrophe ("Flagsmith's own Postgres instance..."),
   and AWS's SG description field only allows a fixed ASCII set with no
   apostrophe — the exact same class of bug ADR-004 already hit once (an em
   dash that time, on `aws_security_group.ops`). `plan` can't catch this;
   it's an apply-time-only AWS API validation. Worth actually internalizing
   this time: **no punctuation beyond `. _-:/()#,@[]+=&;{}!$*` in anything
   that becomes an AWS resource description**, not just "watch out for em
   dashes."
2. **Root volume too small.** AL2023's default 8GB root disk isn't enough
   for this image — confirmed via `aws ec2 get-console-output`:
   `docker: failed to register layer: ... no space left on device`, mid-pull,
   which also failed `cloud-final` and left the instance half-booted with
   no running container. Fixed with an explicit `root_block_device` (30GB
   gp3, encrypted) on the instance. Changing this attribute forced instance
   replacement (confirmed via the EC2 console: old instance state
   `Terminated`, new one `Running`) — worth having verified rather than
   assumed, since an in-place resize alone wouldn't have re-run the already-
   completed `cloud-init`.
3. **Console output needed a workaround to even read, unrelated to AWS.**
   `aws ec2 get-console-output` crashed locally with a Windows codepage
   error (`'charmap' codec can't encode character '→'`) on this
   image's pull-progress output containing a Unicode arrow — worked around
   with `PYTHONUTF8=1 PYTHONIOENCODING=utf-8:replace` and redirecting to a
   file instead of piping to the terminal. Not an infrastructure bug, but
   worth noting since it briefly looked like the instance itself was
   producing no output at all.

## Consequences

- No apply-role IAM changes needed — `rds:*`, `ec2:*`, the project-prefix
  IAM statement, and the broad Secrets Manager statement (added for
  Redis/Cloudflare Tunnel) already covered everything this module creates.
- **Verified live, to the extent currently possible**: `aws ec2
  get-console-output` on the final attempt shows a full image pull, the
  container starting (a container ID printed from `docker run`), and
  `cloud-init` finishing with no errors — strong evidence the fix worked.
  Deeper confirmation (the Flagsmith web UI actually responding, DB
  migrations completing inside the container) isn't available yet: SSM
  still hasn't registered on any ops-subnet instance in this project
  (Flagsmith or the Phase 7 Cloudflare Tunnel instance), and the tunnel has
  no ingress route configured yet to proxy into the VPC from outside.
  Follow-up, not a blocker for this phase's stated scope: either get SSM
  registration working, or wire an actual Cloudflare Tunnel ingress route
  to Flagsmith (and admin access generally) — the latter is really Phase 7
  follow-up work more than Phase 8's.
- Flagsmith's DB and app tier are not yet wired into FastAPI/Celery's
  actual application code (Phase 10/11) — this phase only stands up the
  infrastructure and confirms it boots; using Flagsmith from the app is
  later work.
