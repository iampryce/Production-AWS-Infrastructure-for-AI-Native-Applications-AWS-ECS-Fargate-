#!/bin/bash
set -euxo pipefail

dnf install -y awscli docker jq
systemctl enable --now docker

DB_SECRET_JSON=$(aws secretsmanager get-secret-value \
  --secret-id "${db_secret_arn}" \
  --query SecretString --output text \
  --region "${aws_region}")
DB_PASSWORD=$(echo "$DB_SECRET_JSON" | jq -r '.password')

DJANGO_SECRET_KEY=$(aws secretsmanager get-secret-value \
  --secret-id "${django_secret_key_secret_arn}" \
  --query SecretString --output text \
  --region "${aws_region}")

# Idempotent-ish: fine for this project's one-shot boot, same as the
# Cloudflare Tunnel module - if the DB password or secret key ever rotate,
# replace the instance rather than re-running this.
docker run -d \
  --name flagsmith \
  --restart unless-stopped \
  -p ${flagsmith_port}:8000 \
  -e DATABASE_URL="postgresql://${db_username}:$DB_PASSWORD@${db_host}:${db_port}/${db_name}" \
  -e DJANGO_SECRET_KEY="$DJANGO_SECRET_KEY" \
  -e DJANGO_ALLOWED_HOSTS="*" \
  -e ENVIRONMENT="production" \
  flagsmith/flagsmith:latest
