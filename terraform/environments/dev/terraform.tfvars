aws_region   = "us-east-1"
project_name = "aws-ai-native-infra"

# Cost-optimized, non-prod choice: single shared fck-nat instance rather
# than one per AZ. Prod's terraform.tfvars sets nat_type = "nat-gateway"
# instead, which always gets one NAT Gateway per AZ regardless of fck_nat_ha.
nat_type   = "fck-nat"
fck_nat_ha = false

# Cost-optimized, non-prod choice: single-AZ RDS. Prod's terraform.tfvars
# sets multi_az = true (synchronous standby + automatic failover).
multi_az = false

# Cost-optimized, non-prod choice: single Redis node. Prod's
# terraform.tfvars sets automatic_failover_enabled = true (primary +
# replica across AZs).
automatic_failover_enabled = false

# Registered at Namecheap, no Route 53 hosted zone existed yet - Phase 6
# creates one. Namecheap's nameservers need to be updated to point at it
# before ACM validation (step 2) can succeed.
domain_name = "rivetrecords.online"

# Phase 7. Not a secret - it's an account identifier, not a credential.
# The actual credential (CLOUDFLARE_API_TOKEN) lives in GitHub Actions
# secrets, never here.
cloudflare_account_id = "fa52652a0406755e9d0ae9af7971fc44"

# Gate on the admin subdomain (Jaeger/Flower/Flagsmith) - Cloudflare
# Access sends a one-time PIN to each address here, nothing else gets in.
cloudflare_access_allowed_emails = ["tobilead@gmail.com"]

# Phase 9. Neither of these is a secret - just where and which Grafana
# Cloud stack to send telemetry to. The actual credential
# (GRAFANA_CLOUD_API_KEY) lives in GitHub Actions secrets, never here -
# same as slack_webhook_url, which has no entry here at all.
grafana_cloud_otlp_endpoint = "https://otlp-gateway-prod-us-west-0.grafana.net/otlp"
grafana_cloud_instance_id   = "1732592"
