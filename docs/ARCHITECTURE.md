# Architecture

## Production AWS Infrastructure for AI-Native Applications
Built on Amazon ECS Fargate — async task processing, multi-AZ data layer,
layered observability.

Standalone portfolio project. Not modeled on or affiliated with any
specific company.

## User flow

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
RDS Postgres 16 (pgvector, Alembic)                          AI provider (OpenAI/Gemini/OpenRouter)
                                                                         |
                                                                         v
                                                                  S3 (generated assets)
                                                                         |
                                                                         v
                                                              CloudFront (read path, via OAC)
```

## Multi-AZ network layout

VPC: `10.0.0.0/16`, two availability zones (AZ-a, AZ-b), 7 subnets total.

| Subnet | CIDR | AZ | Purpose |
|---|---|---|---|
| public-a | 10.0.0.0/24 | a | ALB |
| public-b | 10.0.1.0/24 | b | ALB |
| app-a | 10.0.10.0/24 | a | FastAPI + Celery ECS Fargate services |
| app-b | 10.0.11.0/24 | b | FastAPI + Celery ECS Fargate services |
| data-a | 10.0.20.0/24 | a | RDS primary, Redis primary |
| data-b | 10.0.21.0/24 | b | RDS standby, Redis replica |
| ops | 10.0.30.0/24 | a (single AZ) | Cloudflare Tunnel, Flagsmith, OTel collector, Flower |

Security group chain: ALB SG (internet-facing) -> App SG (ALB only) ->
Data SG (App only). Ops SG has no internet-facing inbound rule at all —
reached only via the Cloudflare Tunnel's outbound connection.

RDS runs Multi-AZ (primary + synchronous standby) in prod; ElastiCache
Redis runs as a replication group with automatic failover in prod. Both
default to single-AZ in dev/staging for cost. S3 needs no special
configuration — it's regional and inherently multi-AZ.

## CI/CD — decoupled deploy

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

Terraform owns: VPC, subnets, ECS cluster/task-def-skeleton/service,
ALB, IAM, RDS, Redis, autoscaling policies, CloudFront, WAF, Secrets
Manager references, monitoring resources.

GitHub Actions owns: image build, image push (both tags), rollout
trigger, rollback (by re-pointing `:prod` at a prior SHA and re-running
the deploy step).

## Observability — two independent pipelines

**App-level pipeline** (self-hosted collector -> external SaaS):
FastAPI, Celery, and LLM call sites -> OpenTelemetry (self-hosted
collector in the ops subnet) -> Grafana Cloud (dashboards) + Jaeger
(tracing). Sentry and LangSmith connect via their own SDKs directly,
independent of the OTel collector. Flower runs self-hosted in the ops
subnet purely for Celery queue/worker visibility — a leaf node, no
external forwarding.

**Infra-level pipeline** (fully AWS-native, the one alerting channel):
CloudWatch collects ECS, ALB, RDS, and Redis metrics automatically ->
CloudWatch Alarms -> SNS -> Lambda -> Slack.

## Repo structure

```
project9-ai-native-infra/
  frontend/                  # Next.js 14
  backend/                   # FastAPI, Python 3.11, Alembic migrations
  workers/                   # Celery workers
  terraform/
    modules/
      network/                # VPC, 7 subnets, fck-nat / NAT Gateway
      rds/                     # Postgres 16 + pgvector, multi_az variable
      redis/                   # ElastiCache replication group
      ecs/                     # Fargate cluster, FastAPI + Celery services (shape only)
      cloudfront/              # CDN, OAC, WAF, Route 53, ACM
      cloudflare-tunnel/       # EC2 + cloudflared, replaces bastion
      flagsmith/               # Self-hosted feature flags (EC2 + RDS)
      monitoring/              # CloudWatch, SNS, Lambda, OTel collector config
    environments/
      dev/
      staging/
      prod/
    bootstrap/                 # S3 backend, native S3 state locking, applied once
  .github/
    workflows/
      terraform-dev-plan.yml    # one hardcoded pair per environment, no
      terraform-dev-apply.yml   # dynamic discovery — copy-paste for staging/prod
      image-build-deploy.yml    # decoupled image rollout, SHA + moving tag
  docs/
    ARCHITECTURE.md            # this file
    BUILD_PLAN.md
    COST_NOTES.md
    architecture-diagram.png   # final draw.io export
    ADRs/
    Runbooks/
  README.md
  CLAUDE.md
```

## Key architectural decisions (see ADRs for full reasoning)
1. ECS Fargate, not EKS — two separate services (FastAPI, Celery), not one
2. Multi-AZ networking: 7 subnets, ops subnet single-AZ by deliberate choice
3. RDS Multi-AZ + Redis replication group in prod, single-AZ in dev/staging
4. Terraform owns infra shape; GitHub Actions owns image rollout via a
   moving tag plus an immutable SHA tag for audit/rollback
5. fck-nat in dev/staging, real NAT Gateway per AZ in prod
6. Cloudflare Tunnel on EC2 instead of a bastion host
7. RDS Postgres 16 + pgvector, Alembic migrations
8. Self-hosted Flagsmith for feature flags
9. Two independent observability pipelines: app-level (OTel collector ->
   Grafana Cloud/Jaeger, plus Sentry/LangSmith via direct SDKs, plus
   standalone Flower) and infra-level (CloudWatch -> SNS -> Lambda ->
   Slack as the single alerting channel)
