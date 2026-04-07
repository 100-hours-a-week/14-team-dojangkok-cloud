# HTTP only ALB (임시 실험, ACM 불필요)

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

resource "aws_lb_target_group" "gateway" {
  name     = "${var.project_name}-k8s-gw"
  port     = var.gateway_nodeport
  protocol = "HTTP"
  vpc_id   = var.vpc_id

  health_check {
    enabled             = true
    path                = "/"
    port                = tostring(var.gateway_nodeport)
    protocol            = "HTTP"
    healthy_threshold   = 3
    unhealthy_threshold = 3
    interval            = 30
    timeout             = 5
  }

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-k8s-gw-tg"
  })
}

resource "aws_lb_target_group_attachment" "workers" {
  for_each = var.worker_instances

  target_group_arn = aws_lb_target_group.gateway.arn
  target_id        = each.value
  port             = var.gateway_nodeport
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.gateway.arn
  }
}
