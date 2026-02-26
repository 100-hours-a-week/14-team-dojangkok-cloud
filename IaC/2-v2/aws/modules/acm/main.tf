# ==============================================
# ACM Module
# SSL/TLS Certificates with DNS validation
# ==============================================

terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

resource "aws_acm_certificate" "this" {
  for_each = var.certificates

  domain_name               = each.value.domain_name
  subject_alternative_names = lookup(each.value, "subject_alternative_names", [])
  validation_method         = "DNS"

  tags = {
    Name = "${var.project_name}-${each.key}"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# DNS validation records (output for manual creation in Route53)
# Route53 is NOT in state — records must be created manually or via separate process
