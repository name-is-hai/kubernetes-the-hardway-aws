output "instance_ids" {
  description = "IDs of EC2 instances created by this module"
  value       = aws_instance.this[*].id
}

output "private_ips" {
  description = "Private IP addresses of EC2 instances"
  value       = aws_instance.this[*].private_ip
}

output "names" {
  description = "Name tags of EC2 instances"
  value       = aws_instance.this[*].tags["Name"]
}


output "instance_arns" {
  description = "ARNs of EC2 instances"
  value       = aws_instance.this[*].arn
}
