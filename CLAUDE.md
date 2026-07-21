# Production AWS Infrastructure for AI-Native Applications

Built on Amazon ECS Fargate — async task processing, multi-AZ data layer,
layered observability.

## What this project is
A standalone portfolio project demonstrating production AWS infrastructure
for an AI-native application: an async, AI-assisted content generation
platform (image + personalized message generation). It is not modeled on
or affiliated with any specific company — it is a general-purpose reference
architecture built to demonstrate depth in ECS Fargate, multi-AZ resilience,
decoupled CI/CD, and layered observability for AI workloads. This is a
personal learning and portfolio project, not a production product.

## Purpose
Build a real, working (not mocked) system that a hiring engineer could dig
into at any depth and get a correct, defensible answer — networking,
compute, data resilience, deploy strategy, and observability all included.
Depth on the distinctive architectural choices below matters more than
breadth of AWS services touched.

## Non-negotiable architectural decisions (do not deviate without asking me first)

### Compute
1. **ECS Fargate, NOT EKS/Kubernetes.** All application compute (FastAPI
   API service and Celery worker service) runs as separate ECS Fargate
   services on the same cluster — never combine them into one service or
   one task definition.

### Networking — multi-AZ, 7 subnets total
2. **VPC CIDR**: `10.0.0.0/16`. Two availability zones, AZ-a and AZ-b.
   Subnet plan (do not change without asking):

   | Subnet | CIDR | AZ | Purpose |
   |---|---|---|---|
   | public-a | 10.0.0.0/24 | a | ALB |
   | public-b | 10.0.1.0/24 | b | ALB |
   | app-a | 10.0.10.0/24 | a | FastAPI + Celery ECS Fargate services |
   | app-b | 10.0.11.0/24 | b | FastAPI + Celery ECS Fargate services |
   | data-a | 10.0.20.0/24 | a | RDS primary, ElastiCache Redis primary |
   | data-b | 10.0.21.0/24 | b | RDS standby, ElastiCache Redis replica |
   | ops | 10.0.30.0/24 | a (single AZ, deliberate) | Cloudflare Tunnel EC2, Flagsmith, OTel collector, Flower |

3. **Security group chain**: ALB SG allows inbound from internet only.
   App SG allows inbound from ALB SG only. Data SG allows inbound from App
   SG only — nothing else, not even ops. Ops SG has NO inbound rules from
   the internet; it is reached only via the Cloudflare Tunnel's outbound
   connection. App SG may allow outbound to Ops SG (e.g. to call
   Flagsmith's API or push traces to the OTel collector).

4. **fck-nat in dev/staging, real managed NAT Gateway in prod.** One NAT
   per AZ in prod (no shared single point of failure). Non-prod may use a
   single fck-nat instance if that's the documented cost/resilience
   tradeoff — state it explicitly in the ADR, don't leave it implicit.

### High availability
5. **RDS PostgreSQL 16 with `multi_az = true` in prod** (synchronous
   standby in AZ-b, automatic failover). pgvector extension enabled.
   Migrations via Alembic only — never raw SQL/manual DDL against RDS.
6. **ElastiCache Redis as a replication group with automatic failover
   enabled** in prod — primary in AZ-a, replica in AZ-b.
7. **Dev/staging default to single-AZ** for both RDS and Redis (no
   `multi_az`, single-node replication group) to control cost — mirroring
   the same cost-vs-resilience logic as the fck-nat decision. This must be
   an explicit environment variable, not a hardcoded value, so flipping
   `multi_az = true` for staging later is a one-line change.
8. **S3 is not duplicated per AZ** — it's a regional service, inherently
   multi-AZ. No special HA configuration needed beyond standard bucket
   settings.

### Decoupled deploy strategy — get this exactly right
9. **Terraform owns infra SHAPE only**: ECS cluster, task definition
   skeleton (CPU/mem, IAM roles, log config), ECS service (desired count,
   autoscaling policy), and the service's network configuration (which
   subnets/security groups). Terraform must NEVER own or diff the
   container image URI — if you find yourself putting a specific image
   tag value into a Terraform resource, stop and flag it to me.
10. **GitHub Actions owns the release**, as two things happening together
    on every deploy, not one tag:
    - An **immutable tag** = the git commit SHA (e.g. `:a1b2c3d`) — pushed
      to ECR for every build, permanent, used for audit and rollback.
    - A **moving tag** = `:prod` (or `:staging`) — repointed to that same
      image on every deploy. The ECS task definition references the
      moving tag.
    - After pushing both tags, GitHub Actions calls
      `aws ecs update-service --cluster ... --service ... --force-new-deployment`
      to roll the new image out.
    - Mitigation for the "moving tags reduce auditability" tradeoff is the
      SHA tag plus ECS deployment history — NOT switching to immutable
      tags alone, which would defeat the whole decoupling.

### Observability — two separate pipelines, do not merge them
11. **App-level pipeline (self-hosted collector -> external SaaS)**:
    FastAPI, Celery, and LLM call sites are instrumented with
    OpenTelemetry. A **self-hosted OTel collector** runs in the ops
    subnet and forwards traces/metrics to **Grafana Cloud** (dashboards)
    and **Jaeger** (distributed tracing). **LangSmith** is wired in
    separately via its own SDK at the LLM call sites specifically — it is
    NOT routed through the OTel collector, since it captures
    prompt/token/cost detail that generic OTel spans don't carry.
    **Sentry** is also wired in via its own SDK directly in FastAPI and
    Celery, independent of the OTel collector, for exception/error
    tracking.
12. **Flower** runs self-hosted in the ops subnet, alongside the OTel
    collector, purely for Celery queue/worker visibility. It is a leaf
    node — it doesn't forward data anywhere external, it's a dashboard
    you view directly. Do not group it with the external SaaS
    destinations in diagrams or code comments — it is categorically
    different (self-hosted, not a forwarding destination).
13. **Infra-level pipeline (fully AWS-native, separate from the above)**:
    CloudWatch collects ECS service/task metrics, ALB metrics, and
    RDS/Redis metrics automatically. CloudWatch Alarms trigger through
    **SNS -> Lambda -> Slack** for incident alerting. This is the ONE
    alerting pipeline — do not wire Grafana, Sentry, or any other tool's
    native alerting in addition; the deliberate design choice is a single
    alert channel to avoid alert fatigue from multiple tools paging
    independently.

### Other services
14. **Cloudflare Tunnel on an EC2 instance in the ops subnet**, replacing
    a bastion host entirely. No public bastion should exist anywhere in
    this architecture. The ops subnet has zero inbound internet routes.
15. **Self-hosted Flagsmith** for feature flags — its own EC2 instance
    plus its own small RDS instance, in the ops subnet. Called internally
    over the VPC by FastAPI/Celery, never exposed publicly.
16. **Secrets**: always AWS Secrets Manager via Terraform data sources.
    Never hardcoded, never a plain env var holding a secret value, never
    committed to git.

## Stack
- Frontend: Next.js 14
- Backend: FastAPI, Python 3.11
- Workers: Celery, on ECS Fargate (separate service from FastAPI)
- Database: RDS PostgreSQL 16 + pgvector, Alembic migrations
- Cache/queue: ElastiCache Redis
- AI: OpenAI / Gemini / OpenRouter APIs
- Infra: Terraform, AWS (ECS Fargate, RDS, ElastiCache, S3, CloudFront,
  WAF, Route 53, ACM, ECR, Lambda, Secrets Manager, SNS)
- CI/CD: GitHub Actions (Terraform plan-on-PR/apply-on-main; separate
  decoupled image build-and-deploy workflow)
- Observability: OpenTelemetry (self-hosted collector), Grafana Cloud,
  Jaeger, Sentry, LangSmith, Flower, CloudWatch, SNS, Lambda, Slack

## Repo structure
See `docs/ARCHITECTURE.md` for the full layout. Do not restructure it
without asking first.

## Working style — read this before doing anything
- **Follow `docs/BUILD_PLAN.md` phase by phase.** Only work on the phase I
  tell you to work on. Do not jump ahead, and do not silently expand scope
  within a phase. If you think later-phase work is needed to finish the
  current one, stop and ask me.
- **Never run `terraform apply` against real AWS without showing me the
  plan first and getting explicit confirmation.**
- **After finishing each infrastructure module**, write a short ADR in
  `docs/ADRs/` explaining the decision and tradeoffs in plain, spoken
  language — the way I'd actually explain it out loud in an interview.
  Ask me to review it before moving to the next phase.
- Favor real, working, minimal code over placeholder/mock code. If
  something can't be verified live (e.g. no AWS credentials available),
  say so explicitly rather than faking success.
- If a request from me conflicts with one of the non-negotiable decisions
  above, point out the conflict before proceeding instead of just going
  along with it.
- Every environment-specific choice (multi-AZ on/off, NAT type, instance
  sizing) must be a Terraform variable with a documented default per
  environment — never hardcoded into a module.
