module "control_plane_intances" {
  source = "../../modules/ec2"

  ami_id               = var.ami_control_plane_id
  instance_count       = 3
  instance_type        = "t3.small"
  iam_instance_profile = aws_iam_instance_profile.control_plane_ssm_profile.name
  subnet_ids           = values(module.vpc.private_subnet_ids)
  security_group_ids   = [module.control_plane_security_group.security_group_id]
  role                 = "control-plane"
  name_prefix          = "cp"
}

module "worker_intances" {
  source = "../../modules/ec2"

  ami_id               = var.ami_worker_id
  instance_count       = 3
  instance_type        = "t3.medium"
  iam_instance_profile = aws_iam_instance_profile.worker_ssm_profile.name
  subnet_ids           = values(module.vpc.private_subnet_ids)
  security_group_ids   = [module.worker_security_group.security_group_id]
  role                 = "worker"
  name_prefix          = "worker"
}
