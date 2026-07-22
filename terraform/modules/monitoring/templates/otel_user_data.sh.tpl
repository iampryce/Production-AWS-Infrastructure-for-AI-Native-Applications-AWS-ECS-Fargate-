#!/bin/bash
set -euxo pipefail

dnf install -y awscli docker
systemctl enable --now docker

docker network create observability

GRAFANA_API_KEY=$(aws secretsmanager get-secret-value \
  --secret-id "${grafana_cloud_api_key_secret_arn}" \
  --query SecretString --output text \
  --region "${aws_region}")

AUTH_HEADER=$(printf '%s' "${grafana_cloud_instance_id}:$GRAFANA_API_KEY" | base64 -w0)

mkdir -p /opt/otel
cat > /opt/otel/config.yaml <<EOF
${otel_collector_config}
EOF

# Self-hosted, all-in-one, in-memory storage - a real distributed-tracing
# UI without a separate storage backend (Elasticsearch/Cassandra) this
# project has no other use for. Traces don't survive a container restart,
# which is an accepted tradeoff for a demo, not a production tracing
# store. Named "jaeger" specifically so the collector container can reach
# it by that hostname on the shared docker network.
docker run -d \
  --name jaeger \
  --network observability \
  --restart unless-stopped \
  jaegertracing/all-in-one:latest

docker run -d \
  --name otel-collector \
  --network observability \
  --restart unless-stopped \
  -p 4317:4317 \
  -p 4318:4318 \
  -v /opt/otel/config.yaml:/etc/otelcol-contrib/config.yaml \
  otel/opentelemetry-collector-contrib:latest
