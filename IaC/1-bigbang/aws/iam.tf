resource "aws_iam_role" "s3_access" {
  name = "${var.project_name}-role-s3-bucket"

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
    Name = "${var.project_name}-role-s3-bucket"
  }
}

resource "aws_iam_instance_profile" "s3_access" {
  name = "${var.project_name}-role-s3-bucket"
  role = aws_iam_role.s3_access.name
}

resource "aws_iam_role_policy_attachment" "s3_full_access" {
  role       = aws_iam_role.s3_access.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.s3_access.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}
