#!/bin/bash
set -euxo pipefail

dnf install -y awscli

curl -fsSL https://pkg.cloudflare.com/cloudflared.repo -o /etc/yum.repos.d/cloudflared.repo
dnf install -y cloudflared

TUNNEL_TOKEN=$(aws secretsmanager get-secret-value \
  --secret-id "${tunnel_token_secret_arn}" \
  --query SecretString --output text \
  --region "${aws_region}")

# Idempotent-ish: `service install` fails on a re-run because the systemd
# unit already exists. Fine for this project's one-shot boot - if the token
# ever needs to rotate, replace the instance rather than re-running this.
cloudflared service install "$TUNNEL_TOKEN"
systemctl enable cloudflared
systemctl restart cloudflared
