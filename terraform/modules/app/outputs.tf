output "alb_dns_name" {
  value = aws_lb.this.dns_name
}

output "alb_zone_id" {
  description = "Needed later for a Route 53 alias record (DNS failover)."
  value       = aws_lb.this.zone_id
}

output "app_url" {
  value = "${local.https_enabled ? "https" : "http"}://${aws_lb.this.dns_name}"
}

output "autoscaling_group_name" {
  value = aws_autoscaling_group.app.name
}

output "log_group_name" {
  value = aws_cloudwatch_log_group.app.name
}
