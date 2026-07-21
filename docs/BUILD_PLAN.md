# Build Plan

Work through these phases **in order**. Do not start a phase until the
previous one is confirmed working and its ADR (if applicable) is written.
At the start of every phase, re-read `CLAUDE.md` first — this build plan
assumes its non-negotiable decisions are already loaded into context.

---

### Phase 0 — Repo scaffolding
- Create the directory structure from `docs/ARCHITECTURE.md`.
- Initialize git, add `.gitignore` (Terraform state, `.env`, `__pycache__`,
  `node_modules`, etc.).
- Write `README.md` with: project title ("Production AWS
  Infrastructure for AI-Native Applications"), one-line description,
  stack summary, links to `docs/ARCHITECTURE.md` and `docs/BUILD_PLAN.md`.
  No company references anywhere.
- Set up the Terraform S3 backend as its own bootstrap module (state
  bucket, versioned + encrypted), applied once, separately from
  everything else. State locking uses Terraform's native S3 locking
  (`use_lockfile = true` in each environment's backend block, Terraform
  >= 1.10) — no DynamoDB table needed.
- Output: empty-but-structured repo, committed.

### Phase 1 — Networking module (multi-AZ from the start)
- `terraform/modules/network`: VPC `10.0.0.0/16`, 7 subnets exactly per
  the table in `CLAUDE.md` (2 public, 2 app, 2 data, 1 ops).
- Route tables: public subnets route to an internet gateway. App and data
  subnets route outbound through NAT (fck-nat in dev/staging, real NAT
  Gateway per-AZ in prod — both as a variable-driven choice). Ops subnet
  routes outbound through NAT too, with NO inbound route from the internet
  gateway at all.
- Security groups exactly per the chain in `CLAUDE.md` item 3: ALB SG <-
  internet; App SG <- ALB SG only; Data SG <- App SG only; Ops SG has no
  internet-facing inbound rule.
- `terraform plan` only — show me before applying.
- Write `docs/ADRs/ADR-001-multi-az-subnet-design.md` covering: why 7
  subnets instead of fewer, why ops is single-AZ while app/data are not,
  and the fck-nat/NAT Gateway split by environment.

### Phase 2 — Database module
- `terraform/modules/rds`: RDS PostgreSQL 16, pgvector extension enabled,
  placed across the two data subnets, `multi_az` as a variable (true in
  prod, false by default in dev/staging).
- Alembic set up in `backend/` with an initial migration plus one example
  migration adding a `vector` column, to prove the pgvector path works.
- Write `docs/ADRs/ADR-002-pgvector-alembic-and-multi-az-rds.md`.

### Phase 3 — Redis module
- `terraform/modules/redis`: ElastiCache Redis as a replication group,
  automatic failover as a variable (true in prod, false by default in
  dev/staging), placed across the two data subnets.
- Write `docs/ADRs/ADR-004-elasticache-replication-and-sizing.md`.

### Phase 4 — ECS Fargate module (infra shape only, two services)
- `terraform/modules/ecs`: one cluster, TWO separate task definitions and
  TWO separate services — one for FastAPI, one for Celery workers. Both
  reference the app subnets (both AZs) in their network configuration.
- Task definitions use a placeholder image reference via variable, with a
  comment flagging clearly that the real image is managed outside
  Terraform — do not wire a specific tag in.
- Autoscaling policy per service (state clearly in the ADR whether you're
  scaling on CPU, memory, or ALB request count per target).
- Write `docs/ADRs/ADR-005-ecs-fargate-vs-eks-and-two-services.md` —
  cover both why Fargate over EKS, and why FastAPI and Celery are
  separate services rather than one.

### Phase 5 — Decoupled deploy pipeline (get this exactly right)
- **Terraform GitOps pair pulled forward to right after Phase 2** (see
  "CI/CD pulled forward" note below) — `terraform-plan-on-pr.yml` and
  `terraform-apply-on-main.yml` already exist and are in use from Phase 3
  onward. Nothing left to do for that part here.
- `.github/workflows/image-build-deploy.yml`:
  1. Build the image.
  2. Push to ECR tagged with the git SHA (immutable).
  3. Re-tag/push the same image as `:prod` (or `:staging`) — the moving
     tag.
  4. Call `aws ecs update-service --cluster ... --service ... --force-new-deployment`
     for the relevant service (FastAPI or Celery, whichever changed).
  This workflow must never touch Terraform state or call `terraform apply`
  — it only builds/pushes images and rolls the ECS service, same
  separation of concerns as the plan/apply pair being infra-only.
- Write `docs/ADRs/ADR-006-decoupled-deploy-strategy.md` — this is the
  most important ADR in the project. Explicitly address: why two tags
  (SHA + moving) instead of one, how rollback works (re-run the workflow
  pointing `:prod` at a prior SHA), and how deployment history is
  recovered despite the moving tag (ECS deployment events + the SHA tag
  as the audit trail).

---

### CI/CD pulled forward (mid-Phase-2 decision)

Originally the Terraform plan/apply GitHub Actions pair was scheduled for
Phase 5 alongside the image deploy pipeline. That got moved earlier — no
`terraform apply` runs from a local terminal from this point on, only
through GitHub Actions. What was added, ahead of schedule:

- `terraform/bootstrap/github-oidc.tf`: reuses the existing GitHub OIDC
  provider in this AWS account (one per account, shared across projects)
  and adds two **new, project-scoped** IAM roles:
  - `aws-ai-native-infra-github-actions-plan` — `ReadOnlyAccess`, assumable
    from any branch/PR of this repo. Can never mutate infrastructure.
  - `aws-ai-native-infra-github-actions-apply` — read-write, but the OIDC
    trust condition restricts it to `ref:refs/heads/main` only. Its
    permission policy is scoped to what Phases 0-2 actually use (EC2, RDS,
    Secrets Manager read, IAM limited to this project's naming prefix, and
    this project's own state bucket) — expand it phase by phase as new
    modules land, not upfront.
- `.github/workflows/terraform-plan-on-pr.yml` and
  `terraform-apply-on-main.yml`: a dynamic matrix discovers which
  `terraform/environments/*` directories actually have a `main.tf`, so
  adding staging/prod later needs no workflow edits. Plan runs (and
  comments the output) on every PR touching `terraform/**`; apply runs on
  push to `main`, one environment at a time, each tied to a GitHub
  Environment of the same name (`dev`/`staging`/`prod`) so required
  reviewers can be added per environment as a repo setting.

See `docs/ADRs/ADR-003-cicd-pulled-forward-oidc.md`.

### Phase 6 — Edge / CDN / WAF
- `terraform/modules/cloudfront`: CloudFront distribution with Origin
  Access Control (OAC) to the S3 asset bucket, WAF web ACL attached,
  Route 53 record, ACM certificate. Confirm the request path is Route 53
  -> CloudFront (with WAF attached at the edge) -> ALB, not WAF as a
  separate sequential hop.
- Write `docs/ADRs/ADR-007-cloudfront-oac-and-waf.md`.

### Phase 7 — Cloudflare Tunnel (replaces bastion)
- `terraform/modules/cloudflare-tunnel`: EC2 instance in the ops subnet
  running `cloudflared`, tunnel config, zero inbound security group rules
  from the internet.
- Write `docs/ADRs/ADR-008-cloudflare-tunnel-vs-bastion.md`.

### Phase 8 — Self-hosted Flagsmith
- `terraform/modules/flagsmith`: EC2 instance in the ops subnet running
  Flagsmith, its own small RDS instance, wired to Secrets Manager for its
  own DB credentials. Reachable only from the app subnets (internal VPC
  traffic) and via the Cloudflare Tunnel for admin access.
- Write `docs/ADRs/ADR-009-self-hosted-flagsmith.md`.

### Phase 9 — Observability stack (two pipelines, built as designed)
- `terraform/modules/monitoring`:
  - CloudWatch alarms on ECS service/task metrics, ALB metrics, RDS/Redis
    metrics -> SNS topic -> Lambda -> Slack webhook. This is the ONE
    alerting pipeline.
  - OpenTelemetry collector deployed in the ops subnet, config as code,
    exporting to Grafana Cloud and Jaeger.
- Sentry SDK wired directly into FastAPI and Celery (not through the
  collector).
- LangSmith SDK wired directly at the LLM call sites (not through the
  collector).
- Flower deployed in the ops subnet, self-hosted, standalone — no
  external forwarding.
- Write `docs/ADRs/ADR-010-observability-two-pipelines.md` — explicitly
  explain why alerting is CloudWatch-only and why Sentry/LangSmith bypass
  the OTel collector via their own SDKs.

### Phase 10 — Backend application code
- FastAPI app: submit a generation request, check status, retrieve a
  result. Talks to Postgres (Alembic-migrated models) and enqueues jobs
  to Celery via Redis. Keep it thin and real, no mocked business logic.

### Phase 11 — Worker application code
- Celery worker(s): consume the queue, call the AI provider, store the
  result in S3, update job status in Postgres. Handle rate limits and
  provider errors with retry/backoff — don't crash the worker.

### Phase 12 — Frontend
- Minimal Next.js 14 app: submit a request, poll/see the result. No need
  for polish — this proves the pipeline works end to end.

### Phase 13 — Runbooks
- `docs/Runbooks/redis-queue-saturation.md`
- `docs/Runbooks/alembic-migration-rollback.md`
- `docs/Runbooks/ecs-deployment-failure-and-rollback.md`
- `docs/Runbooks/rds-failover.md`
- Each runbook: symptom -> diagnosis steps -> mitigation -> follow-up.

### Phase 14 — Cost review pass
- `docs/COST_NOTES.md`: for every module, the monthly cost driver and the
  cheapest safe alternative even if not chosen, including the explicit
  multi-AZ cost delta (RDS Multi-AZ roughly doubles instance cost; Redis
  replication group adds a second node) versus the single-AZ dev/staging
  default.

### Phase 15 — Architecture diagram and docs polish
- Finalize the draw.io architecture diagram matching every decision above
  (multi-AZ subnet layout, the two-branch CI/CD fork, the split
  observability pipelines, ops subnet as its own dashed container).
- Title: "Production AWS Infrastructure for AI-Native
  Applications" with subtitle "Built on Amazon ECS Fargate — async task
  processing, multi-AZ data layer, layered observability."
- Export the diagram and place it in `docs/architecture-diagram.png` (or
  `.svg`), referenced from `README.md`.

---

## Rules while executing this plan
- One phase per work session unless I explicitly say to combine phases.
- If AWS credentials/access aren't available when a phase needs to
  actually provision something, still write all the Terraform/code, run
  `terraform validate` and `terraform plan` if possible, and clearly tell
  me what couldn't be verified live.
- Commit at the end of every phase with a clear commit message
  (e.g. `phase-4: ECS Fargate module, two services, infra-shape-only`).
