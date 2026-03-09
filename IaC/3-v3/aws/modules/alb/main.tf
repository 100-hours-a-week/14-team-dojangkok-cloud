# ============================================================
# V3 K8S IaC — ALB (단일 TG, NodePort 포워딩)
# V2 대비: 경로 분기 제거 (Gateway Fabric이 처리)
# Branch: feat/v3-k8s-iac
# ============================================================

resource "aws_lb" "this" {
  name               = "${var.project_name}-k8s-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = var.security_group_ids
  subnets            = var.subnet_ids

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-k8s-alb"
  })
}

# --- Target Group: Gateway Fabric NodePort ---

resource "aws_lb_target_group" "gateway" {
  name     = "${var.project_name}-k8s-gw"
  port     = var.gateway_nodeport
  protocol = "HTTP"
  vpc_id   = var.vpc_id

  health_check {
    enabled             = true
    path                = var.health_check_path
    port                = tostring(var.gateway_nodeport)
    protocol            = "HTTP"
    healthy_threshold   = 3
    unhealthy_threshold = 3
    interval            = 30
    timeout             = 5
  }

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-k8s-gateway-tg"
  })
}

# --- Worker Registration ---

resource "aws_lb_target_group_attachment" "workers" {
  for_each = var.worker_instances

  target_group_arn = aws_lb_target_group.gateway.arn
  target_id        = each.value
  port             = var.gateway_nodeport
}

# --- Listeners ---

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

    # HTTPS 없을 때 직접 포워딩 (dev 환경)
    target_group_arn = var.ssl_certificate_arn == null ? aws_lb_target_group.gateway.arn : null
  }
}

resource "aws_lb_listener" "https" {
  count = var.ssl_certificate_arn != null ? 1 : 0

  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.ssl_certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.gateway.arn
  }
}
