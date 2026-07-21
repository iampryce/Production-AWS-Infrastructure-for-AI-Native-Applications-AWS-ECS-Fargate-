# ADR-001: Multi-AZ Subnet Design (7 Subnets, Ops Single-AZ, NAT Split by Environment)

## Status

Accepted

## Context

The platform needs a VPC that can actually survive an availability zone
outage where it matters (the customer-facing request path) without paying
full multi-AZ cost everywhere it doesn't matter (internal ops tooling). It
also needs a cost story for non-prod that doesn't just mean "smaller
instances" — NAT Gateway alone is one of the more surprisingly expensive
line items in a small AWS bill (hourly charge plus per-GB processed), so
non-prod needed a real answer for that too.

## Decision

**7 subnets, not fewer.** Three tiers — public, app, data — each split
across two AZs (2 + 2 + 2 = 6), plus one ops subnet that's deliberately
single-AZ (7th). VPC is `10.0.0.0/16`, subnets are `/24`s with gaps between
tiers (`.0`/`.1`, `.10`/`.11`, `.20`/`.21`, `.30`) so each tier can grow
without renumbering the whole VPC later.

Why not fewer subnets — like one shared "private" subnet per AZ instead of
splitting app and data? Because the security group chain (ALB → App → Data)
is only half the story; the other half is that app and data genuinely have
different blast radii and different things attach to them (ECS ENIs on one
side, RDS/Redis on the other). Keeping them as separate subnets, even
though they currently share a route table per AZ, means I can tighten NACLs
or split routing later — for example, adding a VPC endpoint that only the
data subnets should see — without re-cutting the network.

**Why ops is single-AZ while app and data are not.** The ops subnet holds
Cloudflare Tunnel, Flagsmith, and the OTel collector — none of that sits on
the customer-facing request path. If that subnet's single instance goes
down, feature flag lookups and traces get temporarily stale/missing, and
internal admin access drops — annoying, not an outage anyone's paying
for. Paying for AZ redundancy on the request path (ALB, ECS tasks, RDS,
Redis) and explicitly not paying for it on the ops tier is the same
cost-vs-resilience call this project makes everywhere else — I'd rather be
able to say "I chose not to" than have someone find a gap I didn't notice.

**NAT split by environment, not by module.** This was the more interesting
decision to get right. The naive move is "fck-nat is cheaper, use it
everywhere except prod, one instance per environment." Real NAT Gateway is
a fully managed, AWS-operated service — no patching, scales automatically,
and is the thing you want between your production traffic and a total
outage. fck-nat is a self-managed EC2 instance running NAT software; it's
dramatically cheaper (a `t4g.micro` instead of NAT Gateway's hourly charge
plus data processing fees) but it's a single instance you're now
responsible for, and if it goes down, everything behind it loses internet
access until it's replaced.

So: **prod always gets one real NAT Gateway per AZ** — no shared single
point of failure, full stop, not a variable anyone can quietly flip.
**Dev/staging default to one shared fck-nat instance across both AZs** —
the documented tradeoff being that if that one instance has a bad day, dev
temporarily can't reach the internet, which is a very different
conversation than production going down. The module also supports
`fck_nat_ha = true` for a fck-nat instance per AZ, in case a future
staging environment needs to test NAT failover behavior cheaply before
prod — but the default is the cheap option, because nothing in dev/staging
needs to survive an AZ outage.

**How the NAT type gets set.** `nat_type` has no default in the network
module itself — every environment's `terraform.tfvars` has to say
`"fck-nat"` or `"nat-gateway"` explicitly. I didn't want an environment to
silently inherit a NAT choice by omission; if someone's reading `dev`'s
tfvars, the tradeoff is right there, not buried in a module default.

**fck-nat AMI, not hardcoded, not "always latest" either.** The module
looks up the current fck-nat AMI live via a `data "aws_ami"` filter against
the official publisher account (`568608671756` — verified directly against
AWS, not assumed), filtered to the `arm64`/AL2023 build. That's a real,
working default rather than a placeholder AMI ID I'd have to remember to
fill in. But it's still overridable via `fck_nat_ami_id` for anyone who
wants to pin an exact build instead of floating to whatever's newest at
apply time — reproducibility is a deliberate opt-in, not automatic.

## Security group chain

`ALB SG` (open to the internet on 443/80) → `App SG` (only reachable from
the ALB SG, on the app port) → `Data SG` (only reachable from the App SG,
on Postgres/Redis ports). `Ops SG` sits outside that chain entirely — no
rule from the internet at all, and its only inbound rules are narrow ones
from the App SG (Flagsmith's API port, the OTel collector's ports). The
only way into the ops subnet from outside the VPC is the Cloudflare
Tunnel's own outbound-initiated connection, which by definition never opens
an inbound port.

The ALB↔App rules specifically had to be built as separate
`aws_vpc_security_group_ingress_rule`/`egress_rule` resources instead of
inline `ingress`/`egress` blocks — with inline blocks, ALB's egress rule
referencing App's SG ID and App's ingress rule referencing ALB's SG ID
creates a dependency cycle Terraform can't resolve (each resource needs the
other to exist first). Splitting the rules into their own resources
resolves the cycle since the SG resources themselves have no inline rules
to create a circular dependency through.

## Consequences

- Both `app-a`/`data-a` and `app-b`/`data-b` currently share one route
  table per AZ (identical routing, since both go to the same AZ's NAT
  target) — a deliberate simplification, not a security shortcut; the
  subnets and security groups stay separate either way.
- Switching an environment from fck-nat to NAT Gateway (or back) is a
  one-line `terraform.tfvars` change, not a module rewrite.
- Prod cannot accidentally end up on fck-nat, because `nat_type` has no
  default anywhere in the chain — it has to be typed out per environment.
