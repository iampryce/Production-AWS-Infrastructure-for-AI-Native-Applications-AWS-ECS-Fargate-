# ADR-008: Cloudflare Tunnel Instead of a Bastion, Terraform-Owned End to End

## Status

Accepted

## Context

The ops subnet (Cloudflare Tunnel EC2, Flagsmith, OTel collector, Flower)
has no internet-facing inbound route at all — CLAUDE.md rules this out
explicitly, and the network module's `ops` security group already has zero
ingress rules from `0.0.0.0/0`. Something still has to let a human reach
that subnet for admin access, without punching a hole in it. Cloudflare
Tunnel does that: `cloudflared`, running on an EC2 instance inside the
subnet, makes an *outbound* connection to Cloudflare's edge, and admin
traffic rides back over that same connection. No listening port, no bastion
host, no public IP on the instance.

The open question wasn't the tunnel concept — CLAUDE.md already settles
that — it was two smaller decisions: how the tunnel's connector *token*
gets into this AWS account, and whether the tunnel needs anything from
this project's DNS (Route 53, already authoritative for `rivetrecords.online`
since Phase 6).

## Decision

### Terraform owns the tunnel, not a manually-pasted token

The first pass at this module had a human create the tunnel by hand in the
Cloudflare Zero Trust dashboard and paste the resulting token into Secrets
Manager via the AWS CLI, with the Terraform module only reading it back via
a data source — mirroring CLAUDE.md's "secrets always via Terraform data
sources" line literally. That was reversed on request: traceability mattered
more here than avoiding one more external credential. The `cloudflare`
Terraform provider now creates the tunnel itself
(`cloudflare_zero_trust_tunnel_cloudflared`, `config_src = "local"`, a
`random_id`-generated `tunnel_secret`), and a `cloudflare_zero_trust_tunnel_cloudflared_token`
data source derives the connector token from that same resource. The token
is a **derived output of a Terraform-managed resource**, not a person-copied
value — same standing as the Redis module's `random_password`-generated AUTH
token, and unlike a data-sourced secret, it shows up in `terraform plan`,
lives in git-tracked module code, and gets destroyed/recreated cleanly with
the rest of the stack.

The tradeoff is a new external credential in scope: the `cloudflare`
provider needs `CLOUDFLARE_API_TOKEN`, scoped narrowly to Account →
Cloudflare Tunnel → Edit (labeled "Argo Tunnel (Legacy)" in the token UI —
Cloudflare renamed the product but not this permission group's internal
name), added as a GitHub Actions secret and read by both the `plan` and
`apply` jobs in `terraform-dev.yml`, the same way the AWS OIDC role is.
`CLOUDFLARE_API_TOKEN` never appears in a `.tf` file or `.tfvars` — the
provider reads it from the environment, same pattern as AWS credentials.

The Cloudflare **account ID** is a separate, non-secret variable
(`cloudflare_account_id` in `terraform.tfvars`) — it identifies which
account owns the tunnel, but grants nothing on its own without the API
token alongside it, so it doesn't need Secrets Manager treatment.

### The connector token still isn't baked into the EC2 launch config

Terraform creates the token, but the EC2 instance doesn't receive it
directly as a `user_data` argument. Instead, Terraform writes it into its
own Secrets Manager secret (`aws_secretsmanager_secret` +
`aws_secretsmanager_secret_version`, same shape as the Redis module's AUTH
token, `recovery_window_in_days = 0` for the same fast-rebuild reason), and
the instance's IAM role is scoped to `secretsmanager:GetSecretValue` on
exactly that one secret ARN. The boot script (`user_data.sh.tpl`) fetches
the value itself via the AWS CLI at boot and hands it to
`cloudflared service install`. Reason: `user_data` is readable via the EC2
API (`DescribeInstanceAttribute`) by a wider set of IAM principals than
Secrets Manager access typically is scoped to — keeping the token out of
the launch configuration keeps its exposure surface to exactly the
`GetSecretValue` policy this module defines, not "anyone who can describe
this instance."

### No key pair, no public IP, no SSH — SSM Session Manager for the box itself

Same no-public-bastion stance as the fck-nat instances (`terraform/modules/network/nat.tf`):
`associate_public_ip_address = false`, no `key_name`, and the instance role
gets `AmazonSSMManagedInstanceCore` attached for direct troubleshooting.
Worth being precise about the split: SSM reaches *this one instance*
directly for its own maintenance; the tunnel is what replaces a bastion for
reaching *everything else* in the ops subnet (Flagsmith, the OTel collector,
Flower) once those land in later phases.

### DNS: Zero Trust's own team domain, not a Route 53 record

Cloudflare Tunnel's *public hostname* feature (routing something like
`ops.rivetrecords.online` through the tunnel) requires the domain's zone to
be Cloudflare-managed — Cloudflare auto-creates the DNS record for a public
hostname inside its own zone. `rivetrecords.online`'s nameservers are
already delegated to Route 53 (Phase 6/ADR-007), and a domain can only be
delegated to one DNS provider's nameservers at a time — adding it to
Cloudflare too would mean moving Namecheap's nameservers away from Route 53,
breaking the already-live ACM/CloudFront/WAF setup. This project doesn't
need that anyway: admin access to the tunnel goes through Cloudflare Zero
Trust's own free team domain (`<team-name>.cloudflareaccess.com`, assigned
automatically on first Zero Trust login — this account's is
`still-cloud-ce0f`), which requires zero DNS changes anywhere. `config_src =
"local"` on the tunnel resource reflects this — routing config lives in the
instance's own `cloudflared` config, not a dashboard-managed public
hostname.

## Consequences

- `terraform/modules/cloudflare-tunnel` now depends on three providers:
  `aws`, `cloudflare`, and `random` — the first module in this project to
  reach outside AWS entirely.
- `CLOUDFLARE_API_TOKEN` joins the AWS OIDC role as a second external
  credential CI depends on, scoped as narrowly as the Cloudflare token UI
  allows (Tunnel Edit only, no Zone access, no DNS access).
- No bootstrap/apply-role IAM changes were needed — the apply role's
  existing `ec2:*`, project-prefix-scoped IAM statement, and broad
  Secrets Manager statement (added for RDS/Redis in earlier phases) already
  cover everything this module creates.
- `terraform validate` is clean for both the module and `environments/dev`.
  The actual `terraform plan`/`apply` run through CI (ADR-003) once this
  change goes through a PR — not yet exercised live as of this ADR; any real
  first-apply surprises (this project has hit a few, per ADR-004/ADR-007)
  get appended here rather than silently fixed.
- A tunnel created by hand in the dashboard during earlier iteration on this
  phase, and the Secrets Manager secret it was briefly stored in, were both
  deleted before this design was finalized — nothing from that manual path
  persists.
