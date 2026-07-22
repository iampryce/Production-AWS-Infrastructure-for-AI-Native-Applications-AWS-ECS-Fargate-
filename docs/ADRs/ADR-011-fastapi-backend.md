# ADR-011: FastAPI Backend — Submit, Check, Retrieve

## Status

Accepted

## Context

BUILD_PLAN's Phase 10 is narrow on purpose: submit a generation request,
check its status, retrieve a result. Talk to Postgres via the
Alembic-migrated schema (Phase 2) and enqueue work to Celery via Redis.
Nothing here calls an AI provider or does any real generation - that's
Phase 11's job, which doesn't exist yet.

## Decision

### Two endpoints, one resource representation

`POST /generations` creates a row and enqueues a job. `GET
/generations/{id}` returns the same shape either way - status, prompt,
`result_url` (null until Phase 11 fills it in). No separate
status-vs-result endpoint: "check status" and "retrieve a result" are the
same read of the same resource, just at different points in its
lifecycle. Simpler than splitting them for no real benefit.

### A new column, in scope for this phase specifically

The existing schema (Phase 2's migrations) had nowhere to put a result.
Added `result_url` (migration 0003) because Phase 10's own stated goal -
"retrieve a result" - has nothing to retrieve without it. This is
different from reaching into Phase 11's territory: the column exists now
because this phase's API needs somewhere to read from, not because
anything here decides how Phase 11's worker populates it.

### Enqueue by task name, not by importing the task

`celery_app.send_task("generate_content", args=[str(id)])` - a string,
not a function reference. The worker that implements `generate_content`
doesn't exist until Phase 11. This keeps FastAPI's code real (a genuine
message lands on the genuine Redis queue, confirmed directly via
`redis-cli LRANGE` during verification, not asserted) without needing
Phase 11's code to exist first, and without FastAPI and the future worker
needing to import from each other.

### Reused the URL-encoding lesson from ADR-010, before hitting it again

Both `app/database.py` (Postgres) and `app/celery_app.py` (Redis) build
connection URLs from a host/port/name plus a password or auth token
pulled from Secrets Manager - and both percent-encode that value before
it goes into the URL. This is the exact bug ADR-010 already found once
(Flower's Redis broker URL breaking on a raw `:` in the AUTH token) -
RDS's managed passwords have the same property (AWS excludes `/`, `"`,
`@` from generated passwords, but not `:`), so the same fix was applied
here proactively rather than waiting to rediscover it.

### A real gap found and fixed: `alembic/env.py` expected a variable nothing sets

Phase 2's `env.py` read `DATABASE_URL` directly - reasonable when written,
since no app convention existed yet to build a connection string from
pieces. Phase 10 established that convention (`DB_HOST`/`DB_NAME`/
`DB_USER`/`DB_SECRET`, matching the ECS task definitions from Phase 4),
and nothing in ECS actually sets `DATABASE_URL` - meaning migrations would
have failed in the real container the same way they did in the first
local `docker-compose up` attempt. Fixed by having `env.py` reuse
`app.database`'s own URL builder (`DATABASE_URL` still works as an
explicit override, useful for one-off local runs) rather than maintaining
two divergent implementations of the same percent-encoding logic.

### Migrations run at container start, not as a separate deploy step

`alembic upgrade head && uvicorn ...` as the Dockerfile's `CMD`. This
project has no dedicated migration-runner ECS task, and Alembic's own
version table plus transactional DDL make concurrent "upgrade head"
attempts across multiple task replicas safe in practice for the
migrations this project has so far. Worth revisiting if a future
migration doesn't hold up under that assumption - noted here rather than
assumed silently.

### Sync SQLAlchemy, not async

`psycopg2` (already installed since Phase 2), plain `Session` objects,
FastAPI's automatic threadpool offload for sync path functions. Adding
`asyncpg` and an async engine would be real complexity for a "keep it
thin" phase with two endpoints - a reasonable point to revisit if this
API's request volume or endpoint count ever justifies it.

## Verified live, twice - locally and in real AWS

**Locally** (`docker-compose up`, Postgres+Redis+backend): all three
migrations applied cleanly, `POST /generations` created a real row,
`GET /generations/{id}` returned it (404 confirmed for a missing id), and
`redis-cli LRANGE celery 0 -1` showed the actual enqueued message with the
correct task name and args.

**In real AWS**, after `image-build-deploy.yml` (Phase 5) built and
shipped the real image: hit the live ALB DNS name directly.
`GET /` returned the real FastAPI JSON health response (`{"status":
"ok"}`), not the old placeholder's `http.server` directory listing -
confirming the real app, not a stale cached one, was actually serving.
`POST /generations` and `GET /generations/{id}` both succeeded against
the live RDS instance through the real deployed task. No Terraform change
was needed to ship this - `use_placeholder_images` was already `false`
from Phase 5, so the existing pipeline picked up the new Dockerfile on
push exactly as designed.

## Consequences

- `backend/app/` now exists as real, running code - no more placeholder
  `http.server` anywhere in this project's compute.
- `docker-compose.yml` (repo root) is the new fast local-verification
  loop for backend/worker changes going forward, not a one-off used only
  for this phase.
- Phase 11's worker, when it implements `generate_content`, inherits two
  things from this phase: the exact task name/args contract already
  proven on the real queue, and the same percent-encoding requirement for
  any Redis or Postgres URL it builds itself.
- Sentry/LangSmith instrumentation (CLAUDE.md item 11) still isn't
  wired in - this phase only proves the request/response/queue path
  works; observability instrumentation of this actual code is follow-up
  work, not blocking.
