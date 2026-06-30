module "packer_security_group" {
  source = "../../modules/security-groups"

  vpc_id                     = module.vpc.vpc_id
  security_group_name        = "packer-security-group"
  security_group_description = "Security group for packer"

  sg_egress_rules = [
    {
      protocol = "tcp"
      port     = 443
      cidr     = "0.0.0.0/0"
    },
    # {
    #   protocol = "tcp"
    #   port     = 53
    #   cidr     = "0.0.0.0/0"
    # },
    # {
    #   protocol = "udp"
    #   port     = 53
    #   cidr     = "0.0.0.0/0"
    # },
  ]
}
