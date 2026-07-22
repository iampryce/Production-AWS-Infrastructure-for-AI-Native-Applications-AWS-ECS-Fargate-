receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4317
      http:
        endpoint: 0.0.0.0:4318

processors:
  batch: {}

exporters:
  # Self-hosted Jaeger, same instance, different container - a dedicated
  # tracing UI reachable without Grafana Cloud credentials.
  otlp/jaeger:
    endpoint: jaeger:4317
    tls:
      insecure: true

  # Grafana Cloud's unified OTLP gateway - traces and metrics both go here
  # too, so Grafana dashboards can correlate them, not just Jaeger.
  #
  # $AUTH_HEADER is deliberately bash syntax, not a Terraform interpolation
  # - it's computed at boot time from a Secrets Manager value Terraform
  # never sees (see otel_user_data.sh.tpl), substituted into this file by
  # the boot script's own heredoc, not by `terraform apply`.
  otlphttp/grafana_cloud:
    endpoint: ${grafana_cloud_otlp_endpoint}
    headers:
      Authorization: "Basic $AUTH_HEADER"

service:
  pipelines:
    traces:
      receivers: [otlp]
      processors: [batch]
      exporters: [otlp/jaeger, otlphttp/grafana_cloud]
    metrics:
      receivers: [otlp]
      processors: [batch]
      exporters: [otlphttp/grafana_cloud]
