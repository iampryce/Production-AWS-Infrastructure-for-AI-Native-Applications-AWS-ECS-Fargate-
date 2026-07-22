#!/bin/bash
set -euxo pipefail

dnf install -y awscli docker
systemctl enable --now docker

REDIS_AUTH_TOKEN=$(aws secretsmanager get-secret-value \
  --secret-id "${redis_auth_token_secret_arn}" \
  --query SecretString --output text \
  --region "${aws_region}")

# rediss:// (TLS) matches the Redis module's transit_encryption_enabled -
# Flower's broker connection has to use the same encrypted transport
# Celery itself does, or it can't reach the same broker at all.
docker run -d \
  --name flower \
  --restart unless-stopped \
  -p ${flower_port}:5555 \
  mher/flower:latest \
  celery \
  --broker="rediss://:$REDIS_AUTH_TOKEN@${redis_host}:${redis_port}/0" \
  flower \
  --port=5555
