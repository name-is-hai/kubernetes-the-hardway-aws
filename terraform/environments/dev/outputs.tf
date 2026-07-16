output "vpc" {
  description = "ID of the VPC used by the k8s-hardway dev environment."
  value       = module.vpc.vpc_id
}

output "packer_iam_instance_profile" {
  description = "IAM instance profile name used by temporary Packer builder instances."
  value       = aws_iam_instance_profile.packer_ssm_profile.name
}

output "control_plane_iam_instance_profile" {
  description = "IAM instance profile name for Kubernetes control-plane instances."
  value       = aws_iam_instance_profile.control_plane_ssm_profile.name
}

output "worker_iam_instance_profile" {
  description = "IAM instance profile name for Kubernetes worker instances."
  value       = aws_iam_instance_profile.worker_ssm_profile.name
}

output "packer_security_group" {
  description = "Security group ID used by temporary Packer builder instances."
  value       = module.packer_security_group.security_group_id
}

output "subnet" {
  description = "Private subnet IDs used for private builders and Kubernetes nodes."
  value       = values(module.vpc.private_subnet_ids)
}

output "control_plane_instance_ids" {
  description = "IDs of Kubernetes control-plane EC2 instances."
  value       = module.control_plane_intances.instance_ids
}

output "control_plane_private_ips" {
  description = "Private IP addresses of Kubernetes control-plane EC2 instances."
  value       = module.control_plane_intances.private_ips
}

output "worker_instance_ids" {
  description = "IDs of Kubernetes worker EC2 instances."
  value       = module.worker_intances.instance_ids
}

output "worker_private_ips" {
  description = "Private IP addresses of Kubernetes worker EC2 instances."
  value       = module.worker_intances.private_ips
}

output "api_nlb_dns_name" {
  description = "DNS name of the internal Kubernetes API Network Load Balancer."
  value       = module.cp_nlb.api_nlb_dns_name
}

output "public_nlb_dns_name" {
  description = "DNS name of the public application Network Load Balancer."
  value       = aws_lb.public_network.dns_name
}

output "api_target_group_arn" {
  description = "ARN of the Kubernetes API target group."
  value       = module.cp_nlb.api_target_group_arn
}

output "control_plane_security_group" {
  description = "Security group ID attached to Kubernetes control-plane instances."
  value       = module.control_plane_security_group.security_group_id
}

output "worker_security_group" {
  description = "Security group ID attached to Kubernetes worker instances."
  value       = module.worker_security_group.security_group_id
}

output "ansible_s3_bucket_name" {
  description = ""
  value       = aws_s3_bucket.ansible.bucket
}
