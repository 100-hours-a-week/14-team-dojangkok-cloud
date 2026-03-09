# ============================================================
# V3 K8S IaC — IAM (K8S 노드 역할 + ECR/EBS/SSM 정책)
# Branch: feat/v3-k8s-iac
# ============================================================

# --- K8S Node Role ---

resource "aws_iam_role" "k8s_node" {
  name = "${var.project_name}-k8s-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })

  tags = var.common_tags
}

# --- Instance Profile ---

resource "aws_iam_instance_profile" "k8s_node" {
  name = "${var.project_name}-k8s-node-profile"
  role = aws_iam_role.k8s_node.name
}

# --- ECR Pull Policy ---

resource "aws_iam_role_policy" "ecr_pull" {
  name = "ecr-pull"
  role = aws_iam_role.k8s_node.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage",
        "ecr:BatchCheckLayerAvailability",
        "ecr:GetAuthorizationToken"
      ]
      Resource = "*"
    }]
  })
}

# --- EBS CSI Driver Policy ---

resource "aws_iam_role_policy" "ebs_csi" {
  name = "ebs-csi"
  role = aws_iam_role.k8s_node.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "ec2:CreateVolume",
        "ec2:DeleteVolume",
        "ec2:AttachVolume",
        "ec2:DetachVolume",
        "ec2:DescribeVolumes",
        "ec2:DescribeInstances",
        "ec2:DescribeAvailabilityZones",
        "ec2:ModifyVolume",
        "ec2:DescribeVolumesModifications",
        "ec2:CreateTags"
      ]
      Resource = "*"
    }]
  })
}

# --- SSM Session Manager Policy ---

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.k8s_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# --- S3 for Ansible SSM file transfer ---

resource "aws_iam_role_policy" "ssm_s3" {
  name = "ssm-s3-transfer"
  role = aws_iam_role.k8s_node.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:GetBucketLocation"
      ]
      Resource = [
        "arn:aws:s3:::dojangkok-v3-ansible-ssm",
        "arn:aws:s3:::dojangkok-v3-ansible-ssm/*"
      ]
    }]
  })
}
