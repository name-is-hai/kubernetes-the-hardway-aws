output "vpc" {
  value = module.vpc.vpc_id
}

output "iam_instance_profile" {
  value = aws_iam_instance_profile.ssm_profile.name
}
