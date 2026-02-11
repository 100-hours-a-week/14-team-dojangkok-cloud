# ==============================================
# IAM 모듈 (import 방식)
#
# 기존 AWS 콘솔에서 생성된 리소스를 terraform import로 관리.
# 리소스 이름은 변수로 받아 기존 이름과 정확히 일치시켜야 함.
#
# Import 명령어 예시:
#   terraform import module.iam.aws_iam_role.ec2 <role_name>
#   terraform import module.iam.aws_iam_instance_profile.ec2 <profile_name>
#   terraform import 'module.iam.aws_iam_role_policy_attachment.ec2["arn:aws:iam::aws:policy/AmazonS3FullAccess"]' <role_name>/arn:aws:iam::aws:policy/AmazonS3FullAccess
#   terraform import module.iam.aws_iam_role.codedeploy[0] <codedeploy_role_name>
# ==============================================

# EC2 Instance Role
resource "aws_iam_role" "ec2" {
  name = var.ec2_role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = var.ec2_role_name
  }
}

# EC2 Instance Profile
resource "aws_iam_instance_profile" "ec2" {
  name = var.ec2_instance_profile_name
  role = aws_iam_role.ec2.name
}

# Policy Attachments (가변 목록)
resource "aws_iam_role_policy_attachment" "ec2" {
  for_each = toset(var.policy_arns)

  role       = aws_iam_role.ec2.name
  policy_arn = each.value
}

# CodeDeploy Role (선택)
resource "aws_iam_role" "codedeploy" {
  count = var.codedeploy_role_name != null ? 1 : 0

  name = var.codedeploy_role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "codedeploy.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = var.codedeploy_role_name
  }
}

resource "aws_iam_role_policy_attachment" "codedeploy" {
  count = var.codedeploy_role_name != null ? 1 : 0

  role       = aws_iam_role.codedeploy[0].name
  policy_arn = "arn:aws:iam::aws:policy/AWSCodeDeployRole"
}
