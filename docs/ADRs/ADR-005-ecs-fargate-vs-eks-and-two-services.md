# ADR-005: ECS Fargate over EKS, and Two Services Instead of One

## Status

Accepted

## Context

The application has two very different workloads that both need to run
continuously: a request/response API (FastAPI) and an async task consumer
(Celery). Both need to run as containers, both need to scale, and both
need the same data-tier access. The two decisions worth being able to
defend out loud are: why Fargate instead of Kubernetes, and why these two
workloads are two separate ECS services instead of one task definition
running both processes.

## Decision

### ECS Fargate, not EKS

This is the more foundational of the two. EKS gives you the full
Kubernetes API — genuinely useful if you already run multiple clusters,
need custom schedulers, or have a team fluent in the Kubernetes ecosystem.
None of that is true here. Fargate gives up that flexibility for less
operational surface: no node group to size, patch, or scale, no cluster
control plane to manage or pay for separately, no CNI/ingress-controller
layer to configure before a container even runs. For two services that
just need "run this container, scale it on CPU, keep it healthy," Fargate
is less to build and less to explain — and it's a deliberate contrast to
a companion portfolio project that already covers EKS, specifically to
demonstrate range across both models rather than defaulting to Kubernetes
for everything.

### Two services, not one task definition running both processes

FastAPI and Celery are genuinely different workloads with different
scaling triggers — FastAPI scales with request volume (CPU from handling
HTTP requests), Celery scales with queue depth (CPU from processing jobs).
Bundling them into one task definition would mean:

- They'd scale together, even though their load doesn't move together —
  a burst of API traffic with an empty queue would scale up idle Celery
  containers alongside the ones actually under load, and vice versa.
- A crash or resource spike in one process could take down the other,
  since they'd share a task's CPU/memory allocation and lifecycle.
- The ALB would need to route only to the FastAPI half of a mixed
  container, which is possible but adds complexity for no real benefit
  over just not mixing them.

Two ECS services on the *same cluster* keeps the operational surface
(one cluster, one set of capacity providers) while keeping the workloads'
scaling and failure domains independent. FastAPI and Celery never sharing
a service or task definition is a hard architectural rule here, not just
a convenience.

### Autoscaling: CPU-based target tracking, not ALB request count

Considered ALB request count as the scaling signal for FastAPI — it's
often the more direct proxy for "is this service under load" for an
HTTP-facing service. Went with CPU instead because it's the one metric
that applies identically to *both* services: Celery has no ALB request
count to scale on at all, and using two different scaling signals for two
services on the same cluster would be a harder thing to explain
consistently ("FastAPI scales on X, Celery scales on Y, here's why they're
different") than one signal applied uniformly. Target value is 70%,
scale-out cooldown 60s (react quickly to load), scale-in cooldown 300s
(don't thrash capacity down the moment load dips).

### Infra shape only — no real image exists yet

Consistent with the decoupled-deploy rule: this module never owns or
diffs a real image tag. Both task definitions default to a public
`python:3.12-slim` image with a command override (`http.server` on the
app port for FastAPI, so it passes a real ALB health check; `sleep
infinity` for Celery, so the task stays alive) — not because a "fake"
image is good enough long-term, but because a task definition needs
*some* pullable image to prove the cluster, services, target group, and
autoscaling policies actually work end to end, since the image
build/deploy pipeline and the real FastAPI/Celery application code don't
exist yet at this point. Swapping
each service's image variable to its own ECR repository's `:prod` tag
later is a deliberate one-time Terraform change, not a per-deploy one —
after that, GitHub Actions rolling a new image never touches Terraform
again.

### HTTP only for now, no HTTPS listener yet

The ALB gets a plain HTTP (port 80) listener for now. An ACM certificate
doesn't exist yet — that comes in a later module covering the edge/CDN/WAF
layer, which is also where CloudFront gets placed in front of this same
ALB. Adding the HTTPS listener is that later module's job, not this one's.

## Consequences

- Two ECR repositories (one per service), an ECS cluster shared by both
  services, an ALB used only by FastAPI, and independent autoscaling
  targets/policies per service.
- Three account-level service-linked roles this AWS account had never
  needed before (`AWSServiceRoleForECS`,
  `AWSServiceRoleForApplicationAutoScaling_ECSService`) had to be added to
  `terraform/bootstrap` proactively — checked for before the first apply
  this time, having learned that lesson from the ElastiCache module
  earlier on (`AWSServiceRoleForElasticLoadBalancing` already existed in
  this account from prior use, so nothing needed there).
- The apply role's IAM policy grew again in the same change that
  introduces this module (`ecs:*`, `ecr:*`, `elasticloadbalancing:*`,
  `application-autoscaling:*`, `logs:*`) rather than discovered through a
  failed run.
- One real bug caught by a local `terraform plan` before this ever reached
  the pipeline: ALB/target group names are capped at 32 characters by
  AWS, and this project's usual `project_name-environment-purpose` naming
  scheme blew past that for the target group. Both the ALB and target
  group names drop the `project_name` prefix as a result — tags still
  carry project/environment identity, the resource name just can't.
