module "cp_nlb" {
  source          = "../../modules/load-balancers"
  nlb_name        = "cp-nlb"
  cp_instance_ids = module.control_plane_intances.instance_ids
  nlb_subnets_ids = values(module.vpc.private_subnet_ids)
  vpc_id          = module.vpc.vpc_id
  nlb_tg_port     = 6443
}
