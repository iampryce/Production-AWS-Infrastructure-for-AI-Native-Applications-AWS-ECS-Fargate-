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
  # the boot script's own heredoc at instance boot, not by Terraform.
  #
  # No backticks anywhere in this file, on purpose: this whole file's
  # rendered text gets spliced into an UNQUOTED heredoc in
  # otel_user_data.sh.tpl, and bash treats backticks as legacy command
  # substitution even inside what looks like a YAML comment - hit this for
  # real (a backtick-quoted "terraform apply" in an earlier version of
  # this comment caused the boot script to actually attempt running
  # "terraform apply" as a shell command mid-heredoc).
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
