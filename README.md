# Production AWS Infrastructure for AI-Native Applications

Built on Amazon ECS Fargate — async task processing, multi-AZ data layer, layered observability.

![Next.js](https://img.shields.io/badge/Next.js-14-black?logo=next.js&logoColor=white)
![FastAPI](https://img.shields.io/badge/FastAPI-009688?logo=fastapi&logoColor=white)
![Python](https://img.shields.io/badge/Python-3.11-3776AB?logo=python&logoColor=white)
![Celery](https://img.shields.io/badge/Celery-37814A?logo=celery&logoColor=white)
![PostgreSQL](https://img.shields.io/badge/PostgreSQL-16%20%2B%20pgvector-4169E1?logo=postgresql&logoColor=white)
![Redis](https://img.shields.io/badge/Redis-ElastiCache-DC382D?logo=redis&logoColor=white)
![Terraform](https://img.shields.io/badge/Terraform-7B42BC?logo=terraform&logoColor=white)
![AWS](https://img.shields.io/badge/AWS-ECS%20Fargate-232F3E?logo=amazonaws&logoColor=white)
![Docker](https://img.shields.io/badge/Docker-2496ED?logo=docker&logoColor=white)
![GitHub Actions](https://img.shields.io/badge/GitHub_Actions-2088FF?logo=githubactions&logoColor=white)
![Cloudflare](https://img.shields.io/badge/Cloudflare_Tunnel-F38020?logo=cloudflare&logoColor=white)
![OpenAI](https://img.shields.io/badge/OpenAI-412991?logo=openai&logoColor=white)
![OpenTelemetry](https://img.shields.io/badge/OpenTelemetry-black?logo=opentelemetry&logoColor=white)
![Grafana](https://img.shields.io/badge/Grafana%20Cloud-F46800?logo=grafana&logoColor=white)
![Jaeger](https://img.shields.io/badge/Jaeger-66CFE3?logo=jaeger&logoColor=white)

## Project Overview

A production-style AWS platform for an **AI-native, asynchronous
content-generation system**: a FastAPI service and Celery workers running as two
independent Amazon ECS Fargate services, generating personalized messages
through OpenAI, backed by a multi-AZ RDS Postgres (with pgvector for
similarity search) and ElastiCache Redis data layer, fronted by CloudFront/WAF, and
released through a fully decoupled Terraform/CI-CD deploy model with a two-pipeline
observability stack (OpenTelemetry, Grafana Cloud, Jaeger, self-hosted Flower on the
application side; CloudWatch → SNS → Lambda → Slack as the single infra alerting
channel).

Every layer — networking, compute, async task processing, data resilience, release
strategy, and observability — is built as real, working infrastructure rather than a
proof of concept. Terraform provisions the shape of the AWS architecture; the platform
running on top of it, submitting a real prompt and getting a real AI-generated result
back through the full pipeline, is the point.

Standalone portfolio project. Not modeled on or affiliated with any specific company.

## Terraform Providers Used

- AWS provider: https://registry.terraform.io/providers/hashicorp/aws/latest
- Cloudflare provider (Phase 7, tunnel module): https://registry.terraform.io/providers/cloudflare/cloudflare/latest
- Archive provider (Phase 9, Lambda packaging): https://registry.terraform.io/providers/hashicorp/archive/latest
- Random provider (secret generation across several modules): https://registry.terraform.io/providers/hashicorp/random/latest

Every module under `terraform/modules/` is hand-written from primitive AWS resources
rather than composed from public registry modules, so each design decision stays
deliberate and explainable end to end.

## Architecture

![alt text](docs/screenshots/heartstamp-infra-demo.gif)

<!-- SCREENSHOT: docs/screenshots/architecture-diagram.png (Phase 15 - final draw.io export) -->

### User flow

```
End users
   |
   v
Route 53 -> CloudFront (WAF attached at the edge) -> ALB
   |
   v
ECS Fargate: FastAPI service  --->  ElastiCache Redis queue  --->  ECS Fargate: Celery workers
   |                                                                    |
   v                                                                    v
RDS Postgres 16 (pgvector, Alembic)                            OpenAI API
                                                                         |
                                                                         v
                                                                  S3 (generated assets)
                                                                         |
                                                                         v
                                                              CloudFront (read path, via OAC)
```

### Multi-AZ network layout

VPC `10.0.0.0/16`, two availability zones, 7 subnets total — see
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the full CIDR table and security group
chain.

### CI/CD — decoupled deploy

```
                      GitHub Actions
                     /              \
                    /                \
      Terraform plan/apply      Build Docker image
      (infra shape only)                |
                                        v
                              Push to ECR:
                              immutable :sha tag
                              + moving :prod tag
                                        |
                                        v
                          aws ecs update-service
                          --force-new-deployment
                                        |
                                        v
                                 ECS Fargate
```

## Infrastructure Overview

**Networking**
- VPC, 2 public subnets, 2 app-tier subnets, 2 data-tier subnets, 1 single-AZ ops subnet
- Internet Gateway
- NAT: fck-nat (dev/staging) or real NAT Gateway per AZ (prod), variable-driven
- Route tables per subnet tier

**Security**
- ALB SG (internet-facing) -> App SG (ALB only) -> Data SG (App only, plus one narrow,
  documented exception for Flower -> Redis); Ops SG has no internet-facing inbound rule
  at all
- IAM roles/policies scoped per ECS task (execution role vs. task role) and per EC2
  instance (Cloudflare Tunnel, Flagsmith, OTel collector, Flower)
- AWS Secrets Manager for every credential — either Terraform-generated
  (`random_password`) or flowed in via `TF_VAR_`-prefixed GitHub Actions secrets, never
  hardcoded, never committed
- WAF Web ACL attached at the CloudFront edge

**Platform**
- ECS Fargate cluster with **two separate services** — FastAPI and Celery — never combined
- RDS PostgreSQL 16 + pgvector, Multi-AZ in prod, Alembic migrations
- ElastiCache Redis as a replication group with automatic failover in prod
- S3 asset bucket, CloudFront with Origin Access Control, Route 53, ACM
- Self-hosted Flagsmith (EC2 + its own RDS) for feature flags
- Cloudflare Tunnel on EC2, replacing a bastion host entirely
- Self-hosted OpenTelemetry collector + Jaeger, Flower (Celery monitoring)
- CloudWatch alarms -> SNS -> Lambda -> Slack, the one infra alerting channel

## Component / Purpose

| Component | Purpose |
|---|---|
| ALB | Routes HTTPS traffic to the ECS FastAPI service |
| ECS FastAPI service | Accepts generation requests, enqueues jobs |
| ECS Celery service | Consumes the queue, calls OpenAI, stores the result |
| RDS Postgres + pgvector | Job/user data, plus embeddings for similarity search |
| ElastiCache Redis | Celery broker |
| S3 | Stores generated message assets |
| CloudFront + WAF | Edge delivery and attack-surface protection for asset reads |
| Flagsmith | Self-hosted feature flag evaluation |
| Cloudflare Tunnel | Outbound-only admin/internal access — no public bastion |
| OTel Collector + Jaeger | App-level traces/metrics -> Grafana Cloud + self-hosted Jaeger |
| Flower | Standalone Celery queue/worker visibility — no external forwarding |
| CloudWatch -> SNS -> Lambda -> Slack | The one infra alerting/paging channel |
| Next.js frontend | Submit a prompt, poll status, see the generated result |

## Platform Engineering Decisions

**ECS Fargate, not EKS.** Two separate ECS services (FastAPI, Celery) on one cluster —
never combined into a single task definition, so each can scale and deploy
independently.

**Terraform owns infra shape; GitHub Actions owns the release.** Terraform never
diffs a container image tag. On every deploy, GitHub Actions pushes an immutable
`:<git-sha>` tag (audit/rollback trail) *and* repoints the moving `:prod` tag, then
calls `aws ecs update-service --force-new-deployment`. Rollback is re-pointing `:prod`
at a prior SHA and re-running the deploy step — a real code path
(`workflow_dispatch` + `rollback_sha`), not just a documented procedure.

**Multi-AZ, but scoped by environment.** RDS Multi-AZ and an ElastiCache replication
group with automatic failover are prod-only, following the same cost/resilience logic
as fck-nat (dev/staging) vs. real NAT Gateway (prod) — non-prod runs single-AZ because
nothing there needs to survive an AZ outage.

**Cloudflare Tunnel instead of a bastion host.** The ops subnet has zero
internet-facing inbound rules; Cloudflare Tunnel's outbound-only connection is the sole
path to internal tooling. The tunnel itself is Terraform-owned end to end via the
Cloudflare provider, not a value pasted in once from the dashboard.

**Self-hosted Flagsmith**, not a SaaS feature-flag vendor — its own EC2 instance and
its own small RDS instance, reachable only internally.

**Two independent observability pipelines, not one fan-out.** App-level: OTel
collector -> Grafana Cloud + self-hosted Jaeger (one EC2, two containers), with Flower
as a standalone self-hosted leaf node. Infra-level: CloudWatch -> SNS -> Lambda ->
Slack, deliberately the *only* alerting channel — avoids alert fatigue from multiple
tools paging independently.

**Secrets always via AWS Secrets Manager.** Either Terraform-generated
(`random_password`, for values with no external origin) or flowed in via
`TF_VAR_`-prefixed GitHub Actions secrets for values that originate outside AWS
entirely (a Cloudflare tunnel token, a Slack webhook, an OpenAI API key) — never
hardcoded, never a plain env var, never committed.

## Project Execution

Status legend: ✅ done · 🔄 in progress · ⬜ planned

### Phase 0 — Repo scaffolding ✅

**Activities**
- Directory structure per `docs/ARCHITECTURE.md`
- Git initialized, `.gitignore` added
- `README.md`, badges
- Terraform bootstrap module written (S3 state bucket, native S3 state locking)
- `terraform plan` reviewed and bootstrap applied by hand — the one deliberate
  exception to "no local apply," since it creates the state bucket and CI/CD's own
  IAM roles before either exists

**Validation**
```powershell
terraform -chdir=terraform/bootstrap init
terraform -chdir=terraform/bootstrap plan
terraform -chdir=terraform/bootstrap apply
```

![S3 backend bootstrap](docs/screenshots/1-S3-backend-boostrap.png)

---

### Phase 1 — Networking module ✅

**Activities**
- VPC `10.0.0.0/16`, 7 subnets (2 public / 2 app / 2 data / 1 ops)
- Route tables per tier; NAT via fck-nat (non-prod) or real NAT Gateway per AZ (prod),
  variable-driven
- Security group chain: ALB -> App -> Data, Ops with zero internet-facing inbound
- `docs/ADRs/ADR-001-multi-az-subnet-design.md`

**Validation**
```powershell
terraform -chdir=terraform/environments/dev plan
aws ec2 describe-vpcs --filters "Name=tag:Project,Values=aws-ai-native-infra" --region us-east-1
aws ec2 describe-subnets --filters "Name=vpc-id,Values=<vpc-id>" --region us-east-1
```

<!-- SCREENSHOT: docs/screenshots/phase-1-networking-plan.png -->

---

### Phase 2 — Database module ✅

**Activities**
- RDS Postgres 16 + pgvector, `multi_az` variable (no default, dev = `false`)
- `manage_master_user_password = true` — RDS-managed Secrets Manager credential, never
  in Terraform state
- Alembic set up in `backend/`, migrations for `generation_requests` +
  `prompt_embedding` (pgvector, HNSW index)
- `docs/ADRs/ADR-002-pgvector-alembic-and-multi-az-rds.md`

**Validation**
```powershell
aws rds describe-db-instances --db-instance-identifier aws-ai-native-infra-dev-pg --region us-east-1 --query 'DBInstances[0].{Status:DBInstanceStatus,MultiAZ:MultiAZ,Engine:EngineVersion}'
alembic upgrade head
```

<!-- SCREENSHOT: docs/screenshots/phase-2-rds-alembic.png -->

---

### CI/CD pulled forward (between Phase 2 and Phase 3) ✅

**Activities**
- OIDC federation to GitHub Actions — no AWS access keys anywhere
- Three project-scoped IAM roles: read-only `plan` (any branch/PR), read-write `apply`
  (trust condition restricted to `main`), and a separate `deploy` role scoped to
  exactly ECR push + `ecs:UpdateService`
- `terraform-dev.yml`: `plan` job on PRs, `apply` job on push to `main`, same file, gated
  by event type
- `docs/ADRs/ADR-003-cicd-pulled-forward-oidc.md`

**Validation**
```powershell
gh pr create --base main --title "..." --body "..."   # triggers plan job
git push origin main                                   # triggers apply job
aws cloudtrail lookup-events --lookup-attributes AttributeKey=EventName,AttributeValue=AssumeRoleWithWebIdentity --region us-east-1
```

**Real bugs found and fixed live**: an OIDC trust-condition mismatch (GitHub's actual
`sub` claim shape differs from the commonly documented format — found via CloudTrail,
not assumed), an ASCII-only security group description (an em dash broke
`CreateSecurityGroup`), and two missing IAM permissions for RDS's KMS/Secrets-Manager
password flow. See ADR-003 for the full incident writeup.

<!-- SCREENSHOT: docs/screenshots/phase-2b-cicd-pipeline.png -->

---

### Phase 3 — Redis module ✅

**Activities**
- ElastiCache Redis 7.1 (verified live against the account before pinning),
  `automatic_failover_enabled` variable (no default, dev = `false`)
- AUTH token generated by Terraform (`random_password`) and stored in its own Secrets
  Manager secret — no AWS-managed equivalent to RDS's feature
- At-rest + in-transit encryption hardcoded on, not a variable
- `docs/ADRs/ADR-004-elasticache-replication-and-sizing.md`

**Validation**
```powershell
aws elasticache describe-replication-groups --replication-group-id aws-ai-native-infra-dev-redis --region us-east-1 --query 'ReplicationGroups[0].{Status:Status,NumNodeGroups:NumNodeGroups}'
```

<!-- SCREENSHOT: docs/screenshots/phase-3-redis.png -->

---

### Phase 4 — ECS Fargate module ✅

**Activities**
- Cluster (FARGATE + FARGATE_SPOT capacity providers), two ECR repos, two task
  definitions, two services — FastAPI behind an ALB, Celery with no load balancer
- CPU-based target-tracking autoscaling on both services
- Placeholder image (`python:3.12-slim` + a command override) — real app code lands in
  Phases 10/11
- `docs/ADRs/ADR-005-ecs-fargate-vs-eks-and-two-services.md`

**Validation**
```powershell
aws ecs describe-services --cluster aws-ai-native-infra-dev --services aws-ai-native-infra-dev-fastapi aws-ai-native-infra-dev-celery --region us-east-1
curl -I http://<alb-dns-name>/
```

<!-- SCREENSHOT: docs/screenshots/phase-4-ecs-healthy-target.png -->

---

### Phase 5 — Decoupled deploy pipeline ✅

**Activities**
- `.github/workflows/image-build-deploy.yml`: builds `backend/Dockerfile` /
  `workers/Dockerfile`, pushes each image under an immutable `:<sha>` tag and the
  moving `:prod` tag, then `aws ecs update-service --force-new-deployment`
- `workflow_dispatch` + `rollback_sha` input — rollback as a real code path (re-point
  `:prod` at an existing SHA tag, no rebuild), not just a documented procedure
- `use_placeholder_images` flipped to `false` once the pipeline had pushed something
  real to `:prod`
- `docs/ADRs/ADR-006-decoupled-deploy-strategy.md` — the most important ADR in the
  project

**Validation**
```powershell
git push origin main   # backend/** or workers/** touched -> triggers image-build-deploy.yml
aws ecr describe-images --repository-name aws-ai-native-infra-dev-fastapi --region us-east-1 --query 'imageDetails[].imageTags'
curl -I http://<alb-dns-name>/
```

<!-- SCREENSHOT: docs/screenshots/phase-5-deploy-pipeline.png -->

---

### Phase 6 — Edge / CDN / WAF ✅

**Activities**
- One CloudFront distribution, two origins (ALB default behavior, uncached; S3 asset
  bucket via OAC on `/assets/*`, cached)
- WAF Web ACL (two AWS managed rule groups + a per-IP rate limit) attached at the edge
- Real registered domain (`rivetrecords.online`) — Route 53 hosted zone, ACM cert for
  apex + `www`, split into two applies to avoid a CI job blocking on DNS propagation
- `docs/ADRs/ADR-007-cloudfront-oac-and-waf.md`

**Validation**
```powershell
curl -I https://rivetrecords.online
# look for: Via: ... (CloudFront), X-Amz-Cf-Pop headers
nslookup rivetrecords.online
```

<!-- SCREENSHOT: docs/screenshots/phase-6-cloudfront-https.png -->

---

### Phase 7 — Cloudflare Tunnel ✅

**Activities**
- EC2 + `cloudflared` in the ops subnet, zero inbound rules from the internet
- Tunnel is Terraform-owned end to end via the `cloudflare` provider (not pasted in
  once from the dashboard) — traceable in state and git
- Connector token derived from the Terraform-managed tunnel resource, stored in its own
  Secrets Manager secret, fetched by the instance at boot
- `docs/ADRs/ADR-008-cloudflare-tunnel-vs-bastion.md`

**Validation**
```powershell
aws ec2 describe-instances --filters "Name=tag:Name,Values=aws-ai-native-infra-dev-cloudflare-tunnel" --region us-east-1 --query 'Reservations[].Instances[].{State:State.Name,PrivateIp:PrivateIpAddress}'
```
Zero Trust dashboard: **Networks -> Tunnels** — status **Healthy**.

<!-- SCREENSHOT: docs/screenshots/phase-7-cloudflare-tunnel-healthy.png -->

---

### Phase 8 — Self-hosted Flagsmith ✅

**Activities**
- EC2 + its own small RDS Postgres instance (data subnets, for a valid 2-AZ subnet
  group), reachable only from the ops SG via a dedicated security group — not the
  shared Data SG
- RDS-managed master password; Terraform-generated Django secret key
- `docs/ADRs/ADR-009-self-hosted-flagsmith.md`

**Validation**
```powershell
aws ec2 describe-instances --filters "Name=tag:Name,Values=aws-ai-native-infra-dev-flagsmith" --region us-east-1 --query 'Reservations[].Instances[].State.Name'
aws rds describe-db-instances --db-instance-identifier aws-ai-native-infra-dev-flagsmith-pg --region us-east-1 --query 'DBInstances[0].DBInstanceStatus'
```

<!-- SCREENSHOT: docs/screenshots/phase-8-flagsmith.png -->

---

### Phase 9 — Observability stack ✅

**Activities**
- CloudWatch alarms (ECS CPU/memory, ALB 5xx/unhealthy hosts, RDS CPU/storage, Redis
  CPU/evictions) -> SNS -> Lambda (stdlib Python, no dependency layer) -> Slack — the
  one alerting channel
- Self-hosted OTel Collector + Jaeger (one EC2, two Docker containers) -> Grafana Cloud
  + self-hosted Jaeger UI
- Self-hosted Flower, standalone — the one deliberate, documented exception to
  "Data SG: App tier only," since Flower has to reach the same Redis broker Celery uses
- `docs/ADRs/ADR-010-observability-two-pipelines.md`

**Validation**
```powershell
aws cloudwatch describe-alarms --alarm-name-prefix aws-ai-native-infra-dev --region us-east-1 --query 'MetricAlarms[].{Name:AlarmName,State:StateValue}'
aws logs tail /ecs/aws-ai-native-infra-dev-celery --since 5m --region us-east-1
```
Real CloudWatch alarm -> SNS -> Lambda -> Slack message received in the configured
channel.

<!-- SCREENSHOT: docs/screenshots/phase-9-slack-alert.png -->
<!-- SCREENSHOT: docs/screenshots/phase-9-grafana-otel.png -->

---

### Phase 10 — Backend application code ✅

**Activities**
- FastAPI: `POST /generations` (creates a row, enqueues `generate_content` by task
  name only — the Celery worker doesn't exist until Phase 11), `GET
  /generations/{id}` (status + result)
- `DATABASE_URL` built and percent-encoded from `DB_HOST`/`DB_NAME`/`DB_USER`/
  `DB_SECRET` (matching the ECS task definition's secrets injection), not a single
  pre-built env var
- Migrations run at container start (`alembic upgrade head && uvicorn ...`)
- `docs/ADRs/ADR-011-fastapi-backend.md`

**Validation**
```powershell
curl -X POST https://rivetrecords.online/generations -H "Content-Type: application/json" -d '{"prompt":"a short congratulations message"}'
curl https://rivetrecords.online/generations/<id>
```

<!-- SCREENSHOT: docs/screenshots/phase-10-fastapi-live.png -->

---

### Phase 11 — Worker application code ✅

**Activities**
- Celery task `generate_content`: fetches the prompt, calls OpenAI (`gpt-4o-mini`),
  uploads the result to the Phase 6 asset bucket (`assets/generations/<id>.json`,
  matching CloudFront's `/assets/*` routing), updates status + `result_url`
- Retries scoped to OpenAI's own transient failure modes only (rate limit, connection,
  timeout, 5xx) with backoff + jitter — a bug in this code fails loudly instead of
  retrying forever
- `status = "failed"` only on genuine final failure (`Task.on_failure`, not a bare
  `except`)
- `docs/ADRs/ADR-012-celery-worker.md`

**Validation**
```powershell
aws logs tail /ecs/aws-ai-native-infra-dev-celery --since 5m --region us-east-1
curl https://rivetrecords.online/assets/generations/<id>.json
```

<!-- SCREENSHOT: docs/screenshots/phase-11-worker-result.png -->

---

### Phase 12 — Frontend ✅

**Activities**
- Minimal Next.js 14 app (`frontend/`): one page, a form that posts to `/generations`,
  then polls `GET /generations/{id}` every 2s until `completed`/`failed`
- Tries to render the result message inline, falls back to a plain link if the
  cross-origin fetch is blocked by CORS
- CORS middleware added to FastAPI (Phase 10 never needed it — its only client had been
  `curl`, which doesn't enforce CORS)

**Validation**
```powershell
cd frontend
npm install
npm run dev
# http://localhost:3000, NEXT_PUBLIC_API_BASE_URL pointed at the live API
```
Verified in an actual browser, not just curl: submitted a real prompt, watched status
go `pending` -> `completed`, saw the real generated message render inline, against the
live deployed backend at `rivetrecords.online`.

<!-- SCREENSHOT: docs/screenshots/phase-12-frontend-ui.png -->

---

### Phase 13 — Runbooks ✅

**Activities**
- `docs/Runbooks/redis-queue-saturation.md`
- `docs/Runbooks/alembic-migration-rollback.md`
- `docs/Runbooks/ecs-deployment-failure-and-rollback.md`
- `docs/Runbooks/rds-failover.md`

Each written against what's actually built — real alarm names, the real `rollback_sha`
mechanism, the real (currently disabled) ECS deployment circuit breaker, the real
dev-vs-prod Multi-AZ behavior split — not generic incident-response boilerplate.

---

### Phase 14 — Cost review pass ⬜
`docs/COST_NOTES.md` — monthly cost driver + cheapest alternative per module,
including the explicit multi-AZ cost delta.

### Phase 15 — Architecture diagram and docs polish ⬜
Final draw.io export to `docs/screenshots/architecture-diagram.png`, referenced from
this README.

See [docs/BUILD_PLAN.md](docs/BUILD_PLAN.md) for full phase detail and
[docs/ADRs/](docs/ADRs/) for decision records.

## Docs

- [Architecture](docs/ARCHITECTURE.md)
- [Build Plan](docs/BUILD_PLAN.md)
- [ADRs](docs/ADRs/)
- [Runbooks](docs/Runbooks/)
- [Screenshots](docs/screenshots/)

## Author

Oluwatobi Ogundimu

GitHub: https://github.com/iampryce

LinkedIn: https://www.linkedin.com/in/oluwatobi-ogundimu-a1341a39b/
