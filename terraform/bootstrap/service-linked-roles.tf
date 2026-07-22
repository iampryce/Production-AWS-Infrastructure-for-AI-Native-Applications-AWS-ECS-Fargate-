# Service-linked roles are account-wide, one-time, and not tied to any
# single environment - they belong here (applied once, by hand, alongside
# the state bucket and CI/CD identity), not inside a reusable module that
# might get instantiated once per environment. Creating this twice would
# just conflict, not duplicate anything useful.
#
# Discovered the hard way: this account had never used ElastiCache before,
# so AWSServiceRoleForElastiCache didn't exist, and CreateCacheSubnetGroup/
# CreateCacheParameterGroup both failed with ServiceLinkedRoleNotFoundFault
# on the first real Redis module apply. The AWS console creates this
# automatically on first use; the API does not.
resource "aws_iam_service_linked_role" "elasticache" {
  aws_service_name = "elasticache.amazonaws.com"
}

# Checked proactively before the Phase 4 (ECS) apply, learning from the
# ElastiCache incident above rather than discovering these the same way a
# second time. This account has used ELB before (AWSServiceRoleForElastic
# LoadBalancing already existed), but never ECS or ECS's own Application
# Auto Scaling integration.
resource "aws_iam_service_linked_role" "ecs" {
  aws_service_name = "ecs.amazonaws.com"
}

resource "aws_iam_service_linked_role" "ecs_autoscaling" {
  aws_service_name = "ecs.application-autoscaling.amazonaws.com"
}
