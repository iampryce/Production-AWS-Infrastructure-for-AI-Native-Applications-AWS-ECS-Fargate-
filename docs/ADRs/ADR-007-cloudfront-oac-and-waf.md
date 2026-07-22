# ADR-007: CloudFront with OAC, WAF at the Edge, and a Real Registered Domain

## Status

Accepted

## Context

Two things needed solving here: how the CDN in front of this platform is
actually shaped (one distribution or several, how it reaches the ALB and
the asset bucket, where WAF sits), and the very real logistics of putting
a real domain (`rivetrecords.online`, registered at Namecheap) in front of
it, which turned out to be its own small story worth documenting honestly
rather than glossing over.

## Decision

### One distribution, two origins — not two hops, not two distributions

The request path is `Route 53 -> CloudFront (WAF attached at the edge) ->
ALB` for everything, with one exception: `/assets/*` routes to the S3
bucket instead, via Origin Access Control. That's a single CloudFront
distribution with two origins and an ordered cache behavior for the asset
path — not WAF as a separate sequential hop in front of the ALB (which
would mean either a second edge layer or WAF attached to the ALB itself,
duplicating what CloudFront already does), and not two separate
distributions for "dynamic" vs. "static" (which would mean two domains or
awkward path-based DNS instead of one coherent site).

The default behavior (ALB) is fully dynamic — no caching
(`min/default/max_ttl = 0`), all methods forwarded, all headers and
cookies forwarded, because it's a live API, not a cacheable site. The
`/assets/*` behavior is the opposite: GET/HEAD only, no cookies, and a real
TTL (`default_ttl = 86400`, `max_ttl = 31536000`) — generated images and
messages don't change once created, so they should actually get cached at
the edge.

### Origin Access Control, not a public bucket

The asset bucket has `block_public_acls`/`block_public_policy` etc. all
`true` — nothing about it is reachable directly. The bucket policy grants
`s3:GetObject` to the `cloudfront.amazonaws.com` service principal, scoped
by an `AWS:SourceArn` condition to *this specific distribution's ARN* —
not "any CloudFront distribution in the account." OAC is the current AWS-
recommended replacement for the older Origin Access Identity approach.

### The ALB gets HTTP-only from CloudFront, on purpose, for now

CloudFront terminates TLS at the edge (`viewer_protocol_policy =
redirect-to-https`); the hop from CloudFront to the ALB origin is
`origin_protocol_policy = "http-only"`, because the ALB still has no HTTPS
listener (the ECS/ALB module built HTTP-only, deliberately deferring the
listener that needs an ACM cert until this module, once a certificate
actually existed). Adding an HTTPS listener to the ALB using this same
certificate is a reasonable next hardening step, but CloudFront-to-ALB
traffic across AWS's own backbone is a materially different threat model
than the public internet — acceptable to defer rather than block this
work on it.

### WAF: two managed rule groups plus one rate limit, not hand-rolled rules

`AWSManagedRulesCommonRuleSet` and `AWSManagedRulesKnownBadInputsRuleSet`
give broad, AWS-maintained coverage against common web exploits and known
bad request signatures — writing custom WAF rules from scratch for a
project this size would mean maintaining a worse version of what AWS
already curates. On top of that, a rate-based rule blocks a single IP once
it crosses `waf_rate_limit` (2000) requests in a rolling 5-minute window —
a different, simpler signal (volume) than the managed rule sets (content),
deliberately layered rather than relied on alone.

WAF for CloudFront must be created with `scope = "CLOUDFRONT"` in
`us-east-1` specifically, regardless of the distribution's actual global
reach — same regional requirement as the ACM certificate, same explicit
provider alias (`aws.us_east_1`) rather than relying on this project's
primary region already happening to be us-east-1.

### The domain: a real, live registrar delegation story

`rivetrecords.online` was registered at Namecheap with no Route 53 hosted
zone in this AWS account yet. Rather than one big apply that includes
`aws_acm_certificate_validation` (which polls until the certificate is
issued), this work was deliberately split in two:

- **Step 1**: create the Route 53 hosted zone, request the ACM
  certificate (apex + `www`), and create the DNS validation `CNAME`
  records. None of this blocks on anything external — it all completes in
  well under a minute.
- **Handoff**: the zone's four nameservers were handed to the registrar
  (Namecheap: Domain -> Nameservers -> Custom DNS). Delegation
  propagation was checked directly against multiple public resolvers
  (Google `8.8.8.8`, Cloudflare `1.1.1.1`, Quad9 `9.9.9.9`) rather than
  assumed — the resolvers didn't even agree with each other mid-
  propagation (Cloudflare picked up the new nameservers before Google
  did), which is normal, and confirms this wasn't something to guess
  about from one query.
- **Step 2**: once all three resolvers agreed and the ACM validation
  `CNAME` records resolved correctly (checked directly, not assumed), the
  `aws_acm_certificate_validation` resource, the S3 bucket, the CloudFront
  distribution, and the WAF Web ACL were added. By this point the apex
  domain had already validated on its own (ACM checks periodically,
  independent of Terraform); `www` validated shortly after within the same
  window.

Splitting it this way meant no CI apply job ever sat blocked on DNS
propagation time it has no control over — a real constraint of committing
to a decoupled, pipeline-only apply model, not something to work around
by applying this step locally instead.

## Consequences

- The apply role's IAM policy grew again in the same changes that
  introduce this module (`route53:*`, `acm:*`, `cloudfront:*`, `wafv2:*`,
  and a project-prefix-scoped S3 statement for the new asset bucket,
  separate from the existing state-bucket-only statement) — not
  discovered via a failed run this time, added proactively based on what
  the module obviously needs.
- `price_class = "PriceClass_100"` (North America + Europe edge locations
  only) is a deliberate cost choice for a demo, not global reach — a real
  production deployment expecting traffic from Asia/South America would
  reconsider this.
- The ALB's HTTP-only origin protocol is a known, stated gap, not an
  oversight — worth mentioning if asked "is this fully hardened," with the
  honest answer being "CloudFront-to-ALB is the one hop still on HTTP, and
  here's why that was an acceptable tradeoff for this module."
