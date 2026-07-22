# ADR-004: ElastiCache Redis — Replication, Sizing, and the AUTH Token

## Status

Accepted

## Context

Celery needs a broker and result backend. Redis is the standard choice
here, and ElastiCache is the managed version of it — same story as RDS for
Postgres: don't run and patch the database software yourself if you don't
have to. The two real decisions were how much AZ redundancy this needs per
environment, and how to handle the credential, since ElastiCache doesn't
have anything like RDS's `manage_master_user_password`.

## Decision

### Same cost/resilience split as everywhere else

`automatic_failover_enabled` is a required variable with no default —
every environment's `terraform.tfvars` sets it explicitly, same pattern as
`nat_type` and `multi_az`. Dev is `false`. When `true` (prod), it drives
two things together: `num_cache_clusters = 2` (a primary and a replica,
one per AZ) and `multi_az_enabled = true` (AWS actually requires
`automatic_failover_enabled` as a prerequisite for `multi_az_enabled` —
they're not independent toggles). When `false`, it's a single node. Same
reasoning as ADR-001 and ADR-002: pay for redundancy on the path that
matters, not by default everywhere.

### Redis 7.1, verified live

Checked `aws elasticache describe-cache-engine-versions` against this
account before picking a version, same discipline as the RDS Postgres
version and the fck-nat AMI — `7.1` is real and available, parameter group
family `redis7` confirmed to match it. Node type is `cache.t4g.micro` —
Graviton, matching the ARM-first cost pattern already used for fck-nat and
RDS in this project.

### No managed password feature here — so this module builds its own

RDS has `manage_master_user_password = true`; ElastiCache doesn't have an
equivalent AWS-managed credential lifecycle for its AUTH token. So this
module generates one itself: a `random_password` (32 chars, special
characters restricted to what ElastiCache's AUTH token actually allows —
it rejects `/`, `"`, and `@`), stored in its own Secrets Manager secret.
The token never appears in a variable, a `.tfvars` file, or a plain
environment variable — only in Terraform state (which lives encrypted in
the private S3 backend) and in Secrets Manager, where Phase 4's ECS task
definitions will reference it directly, the same way they'll reference
RDS's secret.

Encryption is non-negotiable, not a variable: `at_rest_encryption_enabled`
and `transit_encryption_enabled` are both hardcoded `true` — no reason to
ever disable either, so there's no toggle to get wrong. Transit encryption
being on is also *why* an AUTH token is usable at all — ElastiCache
requires it as a prerequisite.

### Lessons already carried over from the RDS/network rollout

Two bugs from Phase 1/2's first real apply directly shaped this module
before it ever touched AWS: every string here that reaches an AWS API
(the replication group's `description`, secret names) is plain ASCII —
no em dashes — after `aws_security_group.ops` broke on exactly that. And
the CI apply role's IAM policy got `elasticache:*` and an expanded
Secrets-Manager statement added *in the same change* that introduces this
module, not discovered the hard way a second time.

### Two more bugs, on the actual first apply

Proactively adding `elasticache:*` and expanding Secrets Manager wasn't
enough — the first real apply still hit two new errors, both new failure
modes not seen in Phase 1/2:

- `CreateCacheSubnetGroup`/`CreateCacheParameterGroup` both failed with
  `ServiceLinkedRoleNotFoundFault`. This AWS account had never used
  ElastiCache before, so `AWSServiceRoleForElastiCache` didn't exist —
  the AWS Console creates it automatically on first use, the API does
  not. Fixed with `aws_iam_service_linked_role` in
  `terraform/bootstrap/service-linked-roles.tf` — deliberately in
  bootstrap, not the `redis` module, since it's account-wide and one-time;
  creating it per-environment would just conflict, not duplicate anything
  useful.
- Creating the Secrets Manager secret failed with `AccessDeniedException`
  on `secretsmanager:GetResourcePolicy` — the AWS provider calls this
  itself as part of reading back a secret right after creating it, which
  wasn't in the apply role's policy since nothing in this project
  attaches resource policies to secrets directly.

## Consequences

- Bootstrap's apply-role policy needed updating again (`elasticache:*`,
  plus the existing Secrets Manager statement now explicitly covers two
  different managed secrets, RDS's and this module's) — applied by hand,
  same as every bootstrap change.
- `terraform plan` reviewed and clean (6 to add: subnet group, parameter
  group, the random password, the Secrets Manager secret + version, and
  the replication group itself) — apply goes through the pipeline like
  everything else since ADR-003, not a local terminal.
- Switching any environment's failover/Multi-AZ posture later is a
  one-line `terraform.tfvars` change, not a module change.
