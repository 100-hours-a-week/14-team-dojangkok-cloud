output "certificate_arns" {
  value = { for k, v in aws_acm_certificate.this : k => v.arn }
}

output "domain_validation_options" {
  value = { for k, v in aws_acm_certificate.this : k => v.domain_validation_options }
}
