# ==============================================
# NLB Module
# Network Load Balancer for TLS passthrough
# (GCP -> AWS RabbitMQ via TLS:5671)
# ==============================================

resource "aws_lb" "this" {
  name               = "${var.project_name}-nlb"
  internal           = false
  load_balancer_type = "network"
  subnets            = var.subnet_ids
  security_groups    = length(var.security_group_ids) > 0 ? var.security_group_ids : null

  tags = {
    Name = "${var.project_name}-nlb"
  }
}

# Target Group
resource "aws_lb_target_group" "this" {
  for_each = var.target_groups

  name     = "${var.project_name}-${each.key}-tg"
  port     = each.value.port
  protocol = "TCP"
  vpc_id   = var.vpc_id

  health_check {
    enabled             = true
    protocol            = "TCP"
    healthy_threshold   = lookup(each.value, "healthy_threshold", 3)
    unhealthy_threshold = lookup(each.value, "unhealthy_threshold", 3)
    interval            = lookup(each.value, "health_check_interval", 30)
  }

  tags = {
    Name = "${var.project_name}-${each.key}-tg"
  }
}

# Target Group Attachment
resource "aws_lb_target_group_attachment" "this" {
  for_each = var.target_group_attachments

  target_group_arn = aws_lb_target_group.this[each.key].arn
  target_id        = each.value.target_id
  port             = each.value.port
}

# TLS Listener
resource "aws_lb_listener" "tls" {
  for_each = { for k, v in var.listeners : k => v }

  load_balancer_arn = aws_lb.this.arn
  port              = each.value.port
  protocol          = each.value.protocol
  ssl_policy        = lookup(each.value, "ssl_policy", each.value.protocol == "TLS" ? "ELBSecurityPolicy-TLS13-1-2-Res-PQ-2025-09" : null)
  certificate_arn   = lookup(each.value, "certificate_arn", null)

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this[each.value.target_group_key].arn
  }
}
