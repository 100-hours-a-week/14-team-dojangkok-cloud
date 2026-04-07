# V3 패턴 재활용: data-driven SG 맵 + aws_security_group_rule

resource "aws_security_group" "this" {
  for_each = var.security_groups

  name        = "${var.project_name}-${each.key}-sg"
  description = each.value.description
  vpc_id      = var.vpc_id

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-${each.key}-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

locals {
  ingress_rules = merge([
    for sg_name, sg in var.security_groups : {
      for idx, rule in sg.ingress_rules :
      "${sg_name}-${idx}" => merge(rule, { sg_name = sg_name })
    }
  ]...)
}

resource "aws_security_group_rule" "ingress" {
  for_each = local.ingress_rules

  type                     = "ingress"
  from_port                = each.value.from_port
  to_port                  = each.value.to_port
  protocol                 = each.value.protocol
  cidr_blocks              = lookup(each.value, "cidr_blocks", null)
  source_security_group_id = lookup(each.value, "source_security_group_id", null)
  description              = lookup(each.value, "description", "")
  security_group_id        = aws_security_group.this[each.value.sg_name].id
}

resource "aws_security_group_rule" "egress" {
  for_each = var.security_groups

  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "Allow all outbound"
  security_group_id = aws_security_group.this[each.key].id
}

# data 인스턴스 SG에 K8S worker → stateful 서비스 인바운드 추가
resource "aws_security_group_rule" "data_mysql" {
  type              = "ingress"
  from_port         = 3306
  to_port           = 3306
  protocol          = "tcp"
  cidr_blocks       = [var.secondary_cidr]
  description       = "FIS K8S workers to MySQL"
  security_group_id = var.data_security_group_id
}

resource "aws_security_group_rule" "data_redis" {
  type              = "ingress"
  from_port         = 6379
  to_port           = 6379
  protocol          = "tcp"
  cidr_blocks       = [var.secondary_cidr]
  description       = "FIS K8S workers to Redis"
  security_group_id = var.data_security_group_id
}

resource "aws_security_group_rule" "data_rabbitmq" {
  type              = "ingress"
  from_port         = 5672
  to_port           = 5672
  protocol          = "tcp"
  cidr_blocks       = [var.secondary_cidr]
  description       = "FIS K8S workers to RabbitMQ"
  security_group_id = var.data_security_group_id
}

resource "aws_security_group_rule" "data_mongodb" {
  type              = "ingress"
  from_port         = 27017
  to_port           = 27017
  protocol          = "tcp"
  cidr_blocks       = [var.secondary_cidr]
  description       = "FIS K8S workers to MongoDB"
  security_group_id = var.data_security_group_id
}
