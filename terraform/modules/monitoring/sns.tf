# The one alerting pipeline (CLAUDE.md item 13) - every CloudWatch alarm
# in this module points here, and this is the only thing subscribed to
# it (the Slack notifier Lambda). No other tool's native alerting gets
# wired in alongside this, on purpose - one channel, no alert fatigue
# from multiple tools paging independently.
resource "aws_sns_topic" "alerts" {
  name = "${var.project_name}-${var.environment}-alerts"
  tags = var.tags
}
