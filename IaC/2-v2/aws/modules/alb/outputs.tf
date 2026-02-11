output "alb_arn" {
  description = "ALB ARN"
  value       = aws_lb.this.arn
}

output "alb_dns_name" {
  description = "ALB DNS 이름"
  value       = aws_lb.this.dns_name
}

output "alb_zone_id" {
  description = "ALB Zone ID (Route53 alias용)"
  value       = aws_lb.this.zone_id
}

output "target_group_arns" {
  description = "Target Group ARN 맵"
  value       = { for k, v in aws_lb_target_group.this : k => v.arn }
}

output "http_listener_arn" {
  description = "HTTP Listener ARN"
  value       = aws_lb_listener.http.arn
}

output "https_listener_arn" {
  description = "HTTPS Listener ARN"
  value       = var.ssl_certificate_arn != null ? aws_lb_listener.https[0].arn : null
}
