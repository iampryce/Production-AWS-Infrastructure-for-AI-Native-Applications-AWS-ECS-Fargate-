#!/bin/bash
set -euxo pipefail

dnf install -y awscli docker
systemctl enable --now docker

REDIS_AUTH_TOKEN=$(aws secretsmanager get-secret-value \
  --secret-id "${redis_auth_token_secret_arn}" \
  --query SecretString --output text \
  --region "${aws_region}")

# The token's charset is chosen to satisfy ElastiCache's own AUTH token
# restrictions (redis module: no '/', '"', '@') - it deliberately still
# allows ':' and other characters that are reserved inside a URL, so it
# has to be percent-encoded before going into the broker URL below or
# kombu/celery can't parse where the password ends (a literal ':' in the
# password reads as a second field separator). python3 is already on
# AL2023 via cloud-init's own dependency, no extra package needed.
REDIS_AUTH_TOKEN_URLENCODED=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe=''))" "$REDIS_AUTH_TOKEN")

# rediss:// (TLS) matches the Redis module's transit_encryption_enabled -
# Flower's broker connection has to use the same encrypted transport
# Celery itself does, or it can't reach the same broker at all.
docker run -d \
  --name flower \
  --restart unless-stopped \
  -p ${flower_port}:5555 \
  mher/flower:latest \
  celery \
  --broker="rediss://:$REDIS_AUTH_TOKEN_URLENCODED@${redis_host}:${redis_port}/0" \
  flower \
  --port=5555
