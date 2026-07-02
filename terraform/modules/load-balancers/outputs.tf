output "api_nlb_dns_name" {
  value = aws_lb.network.dns_name
}

output "api_target_group_arn" {
  value = aws_lb_target_group.network.arn
}
