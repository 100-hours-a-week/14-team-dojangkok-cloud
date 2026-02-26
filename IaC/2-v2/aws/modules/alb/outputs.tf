output "alb_arn" {
  value = aws_lb.this.arn
}

output "alb_dns_name" {
  value = aws_lb.this.dns_name
}

output "alb_zone_id" {
  value = aws_lb.this.zone_id
}

output "target_group_arns" {
  value = { for k, v in aws_lb_target_group.this : k => v.arn }
}

output "http_listener_arn" {
  value = aws_lb_listener.http.arn
}

output "https_listener_arn" {
  value = var.ssl_certificate_arn != null ? aws_lb_listener.https[0].arn : null
}
