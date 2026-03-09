# ============================================================
# V3 K8S IaC — Security Groups (V2 패턴 재활용)
# K8S CP, Worker, NAT 등 SG 정의
# inline 규칙 대신 aws_security_group_rule 사용 (멱등성 보장)
# Branch: feat/v3-k8s-iac
# ============================================================

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

# --- Ingress Rules (flattened) ---

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

# --- Egress Rules (all outbound) ---

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
