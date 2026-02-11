# Application Load Balancer
resource "aws_lb" "this" {
  name               = "${var.project_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = var.security_group_ids
  subnets            = var.subnet_ids

  tags = {
    Name = "${var.project_name}-alb"
  }
}

# Target Groups
resource "aws_lb_target_group" "this" {
  for_each = var.target_groups

  name     = "${var.project_name}-${each.key}-tg"
  port     = each.value.port
  protocol = "HTTP"
  vpc_id   = var.vpc_id

  health_check {
    enabled             = true
    healthy_threshold   = lookup(each.value, "healthy_threshold", 3)
    unhealthy_threshold = lookup(each.value, "unhealthy_threshold", 3)
    timeout             = lookup(each.value, "health_check_timeout", 5)
    interval            = lookup(each.value, "health_check_interval", 30)
    path                = lookup(each.value, "health_check_path", "/")
    matcher             = lookup(each.value, "health_check_matcher", "200")
  }

  tags = {
    Name = "${var.project_name}-${each.key}-tg"
  }
}

# HTTP Listener (redirect to HTTPS or forward)
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = var.ssl_certificate_arn != null ? "redirect" : "forward"

    dynamic "redirect" {
      for_each = var.ssl_certificate_arn != null ? [1] : []
      content {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }

    # Forward to first target group when no SSL
    target_group_arn = var.ssl_certificate_arn == null ? values(aws_lb_target_group.this)[0].arn : null
  }
}

# HTTPS Listener (optional, when SSL cert is provided)
resource "aws_lb_listener" "https" {
  count = var.ssl_certificate_arn != null ? 1 : 0

  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.ssl_certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = values(aws_lb_target_group.this)[0].arn
  }
}

# Listener Rules for path-based routing
resource "aws_lb_listener_rule" "this" {
  for_each = { for k, v in var.target_groups : k => v if lookup(v, "path_pattern", null) != null }

  listener_arn = var.ssl_certificate_arn != null ? aws_lb_listener.https[0].arn : aws_lb_listener.http.arn
  priority     = each.value.priority

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this[each.key].arn
  }

  condition {
    path_pattern {
      values = [each.value.path_pattern]
    }
  }
}
