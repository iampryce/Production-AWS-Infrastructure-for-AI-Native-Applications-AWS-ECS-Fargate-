# HTTP listener only for now - the ACM certificate doesn't exist until
# Phase 6 (Edge/CDN/WAF), which adds the HTTPS listener on top of this
# same ALB. CloudFront will front this ALB once Phase 6 lands.

resource "aws_lb" "this" {
  # ALB/target group names are capped at 32 characters by AWS - shorter
  # than this project's usual naming scheme allows once an environment
  # name is added, so these two drop the project_name prefix. Project/
  # environment identity is still on the tags.
  name               = "${var.environment}-alb"
  internal           = false
  load_balancer_type = "application"
  subnets            = var.public_subnet_ids
  security_groups    = [var.alb_security_group_id]

  tags = var.tags
}

resource "aws_lb_target_group" "fastapi" {
  name        = "${var.environment}-fastapi-tg"
  port        = var.app_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip" # required for Fargate awsvpc networking

  health_check {
    path                = "/"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
    timeout             = 5
    matcher             = "200"
  }

  tags = var.tags
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.fastapi.arn
  }
}
