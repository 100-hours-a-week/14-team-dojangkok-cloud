# ==============================================
# IAM Module (per-service, import 지원)
# for_each로 서비스별 Role + Instance Profile 생성
# ==============================================

resource "aws_iam_role" "this" {
  for_each = var.roles

  name        = each.value.role_name
  description = lookup(each.value, "description", null)

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = lookup(each.value, "service_principal", "ec2.amazonaws.com")
        }
      }
    ]
  })

  tags = {
    Name = each.value.role_name
  }
}

resource "aws_iam_instance_profile" "this" {
  for_each = { for k, v in var.roles : k => v if lookup(v, "create_instance_profile", true) }

  name = each.value.role_name
  role = aws_iam_role.this[each.key].name
}

# Managed policy attachments
locals {
  role_policy_pairs = flatten([
    for role_key, role in var.roles : [
      for policy_arn in lookup(role, "policy_arns", []) : {
        key        = "${role_key}-${replace(policy_arn, "/.*\\//", "")}"
        role_key   = role_key
        policy_arn = policy_arn
      }
    ]
  ])
}

resource "aws_iam_role_policy_attachment" "this" {
  for_each = { for item in local.role_policy_pairs : item.key => item }

  role       = aws_iam_role.this[each.value.role_key].name
  policy_arn = each.value.policy_arn
}

# Inline policy (optional, e.g. CodeDeploy IamAndEc2)
resource "aws_iam_role_policy" "inline" {
  for_each = { for k, v in var.roles : k => v if lookup(v, "inline_policy", null) != null }

  name   = "${each.value.role_name}-inline"
  role   = aws_iam_role.this[each.key].name
  policy = each.value.inline_policy
}
