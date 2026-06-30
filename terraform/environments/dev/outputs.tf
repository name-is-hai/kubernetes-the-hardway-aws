output "vpc" {
  value = module.vpc.vpc_id
}

output "iam_instance_profile" {
  value = aws_iam_instance_profile.ssm_profile.name
}

output "packer_security_group" {
  value = module.packer_security_group.security_group_id
}

output "subnet" {
  value = values(module.vpc.private_subnet_ids)
}
