# ==============================================
# IAM Users / Groups (글로벌 - 환경 무관)
# 기존 콘솔에서 생성된 리소스를 terraform import로 관리
#
# 사용법:
#   terraform import aws_iam_group.deployer deployer
#   terraform import aws_iam_group.developers developers
#   terraform import aws_iam_group.infra_admin InfraAdminGroup
#   terraform import aws_iam_user.deployer ktb-team14-deployer
#   terraform import aws_iam_user.ellen ktb-team14-ellen
#   terraform import aws_iam_user.suho ktb-team14-suho
#   terraform import aws_iam_user.howard ktb-team14-howard
#   terraform import aws_iam_user.waf ktb-team14-waf
# ==============================================

# --- Groups ---
resource "aws_iam_group" "deployer" {
  name = "deployer"
}

resource "aws_iam_group" "developers" {
  name = "developers"
}

resource "aws_iam_group" "infra_admin" {
  name = "InfraAdminGroup"
}

# --- Users ---
resource "aws_iam_user" "deployer" {
  name = "ktb-team14-deployer"
}

resource "aws_iam_user" "ellen" {
  name = "ktb-team14-ellen"
}

resource "aws_iam_user" "suho" {
  name = "ktb-team14-suho"
}

resource "aws_iam_user" "howard" {
  name = "ktb-team14-howard"
}

resource "aws_iam_user" "waf" {
  name = "ktb-team14-waf"
}

# --- Group Membership ---
resource "aws_iam_group_membership" "deployer" {
  name  = "deployer-membership"
  users = [aws_iam_user.deployer.name]
  group = aws_iam_group.deployer.name
}

resource "aws_iam_group_membership" "developers" {
  name  = "developers-membership"
  users = [
    aws_iam_user.ellen.name,
    aws_iam_user.suho.name,
  ]
  group = aws_iam_group.developers.name
}

resource "aws_iam_group_membership" "infra_admin" {
  name  = "infra-admin-membership"
  users = [
    aws_iam_user.howard.name,
    aws_iam_user.waf.name,
  ]
  group = aws_iam_group.infra_admin.name
}

# --- Policy Attachments ---
resource "aws_iam_group_policy_attachment" "deployer_s3_readonly" {
  group      = aws_iam_group.deployer.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
}

resource "aws_iam_group_policy_attachment" "admin_full" {
  group      = aws_iam_group.infra_admin.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

resource "aws_iam_group_policy_attachment" "developers_s3_full" {
  group      = aws_iam_group.developers.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}

resource "aws_iam_policy" "developers_ssm" {
  name        = "developers-ssm-policy"
  description = "Custom SSM Session Manager Policy for Developers"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SessionManagerStart"
        Effect = "Allow"
        Action = ["ssm:StartSession"]
        Resource = [
          "arn:aws:ec2:*:*:instance/*",
          "arn:aws:ssm:*:*:document/AWS-StartSSHSession",
          "arn:aws:ssm:*:*:document/SSM-SessionManagerRunShell",
          "arn:aws:ssm:*:*:document/AWS-StartPortForwardingSession",
        ]
      },
      {
        Sid    = "SessionManagerControl"
        Effect = "Allow"
        Action = [
          "ssm:TerminateSession",
          "ssm:ResumeSession",
        ]
        Resource = ["arn:aws:ssm:*:*:session/$${aws:username}-*"]
      },
      {
        Sid    = "ConsoleViewAccess"
        Effect = "Allow"
        Action = [
          "ssm:DescribeSessions",
          "ssm:GetConnectionStatus",
          "ssm:DescribeInstanceInformation",
          "ssm:DescribeInstanceProperties",
          "ec2:DescribeInstances",
        ]
        Resource = "*"
      },
    ]
  })
}

resource "aws_iam_group_policy_attachment" "developers_ssm_attach" {
  group      = aws_iam_group.developers.name
  policy_arn = aws_iam_policy.developers_ssm.arn
}
