# ADR-002: pgvector, Alembic, and Multi-AZ RDS

## Status

Accepted

## Context

The platform needs to store prompt/style embeddings for similarity search
(finding "cards like this one") right next to the relational data it's
already storing (job status, prompts, timestamps) — so a vector database
bolted on as a separate system was never really on the table; Postgres with
pgvector keeps everything in one place, one connection, one backup
strategy. Two separate problems needed solving: how schema changes to that
database happen safely, and how much AZ redundancy that database actually
needs per environment.

## Decision

### pgvector needs no special infrastructure

RDS Postgres 16 ships with the `vector` extension already available — there
is no parameter group flag, no `rds.allowed_extensions` setting, nothing
Terraform needs to configure. Enabling it is just `CREATE EXTENSION IF NOT
EXISTS vector;`, which is schema DDL, not infrastructure — so it belongs in
an Alembic migration, not the Terraform RDS module. I verified this
directly: ran it against a real Postgres 16 container and confirmed
`vector 0.8.5` installs cleanly with no extra setup.

### All schema changes go through Alembic — never raw SQL against RDS

`backend/alembic/` is wired up with two migrations so far:

- **`0001_create_generation_requests`**: enables the `vector` extension and
  creates the `generation_requests` table (id, status, prompt,
  created_at/updated_at). Uses Postgres's built-in `gen_random_uuid()` for
  the primary key — I checked, this is native to Postgres 16 itself, no
  `pgcrypto` extension needed (that used to be required on older
  versions).
- **`0002_add_prompt_embedding`**: adds a `prompt_embedding vector(1536)`
  column (matching OpenAI's `text-embedding-3-small` dimension) and an
  **HNSW** index over it with `vector_cosine_ops`. I chose HNSW over the
  older `ivfflat` index type deliberately — HNSW doesn't need a training
  step or a tuned list count before it's useful, and gives better recall at
  query time. The tradeoff is slower index builds, which is a fine trade at
  this scale.

`env.py` reads the connection string from `DATABASE_URL` at runtime only —
nothing is ever hardcoded or committed, consistent with the project's
Secrets Manager-only rule for anything credential-shaped.

**I didn't just write these and hope** — I spun up a real `postgres16
+ pgvector` Docker container, ran `alembic upgrade head` against it, and
confirmed by hand: the table, the vector column, the HNSW index, and the
extension all exist exactly as intended. Then ran `alembic downgrade base`
followed by `upgrade head` again to prove the round trip — both directions
actually work, not just the forward path.

### RDS Multi-AZ: prod only, same pattern as everything else here

`multi_az` is a required variable with **no default** in the module — every
environment's `terraform.tfvars` has to say `true` or `false` explicitly.
Dev is `false` (a single instance; nothing here needs to survive an AZ
outage for a one-day demo). Prod will be `true` — a synchronous standby in
the second AZ with automatic failover. Same cost-vs-resilience logic used
for the NAT gateway split between environments: pay for the resilience
where an outage actually costs something, not everywhere by default.

### The master password never exists in Terraform state or config

`manage_master_user_password = true` has RDS create and manage the
password itself, storing it in a Secrets Manager secret it owns and
rotates — I never generate a `random_password`, and there's no plaintext
credential anywhere in this Terraform config, state file, or `.tfvars`.
The module outputs `master_user_secret_arn` so the ECS task definitions
can reference it directly from Secrets Manager, never as a plain
environment variable.

### Cost/teardown defaults for a short-lived environment

`deletion_protection = false` and `skip_final_snapshot = true` by default —
this environment is meant to be built, demonstrated, and torn down cleanly,
not kept running. Prod's `terraform.tfvars` should flip both before this
module is ever pointed at a real production account.

## Consequences

- Standing up the actual RDS instance requires `terraform apply` (not done
  yet — plan reviewed: 48 resources to add, 0 to change/destroy, folded in
  with the network module's resources in the same dev stack).
- Alembic migrations are proven correct against a real Postgres 16 +
  pgvector database, independent of whether the real RDS instance exists
  yet — so there's nothing left to "trust me, it should work" about this
  piece.
- Switching `multi_az` for any environment later is a one-line
  `terraform.tfvars` change, not a module or migration change.
