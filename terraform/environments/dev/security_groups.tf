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
  ]
}

module "control_plane_security_group" {
  source = "../../modules/security-groups"

  vpc_id                     = module.vpc.vpc_id
  security_group_name        = "control-plane-security-group"
  security_group_description = "Security group for control plane"

  sg_egress_rules = [
    {
      protocol = "tcp"
      port     = 443
      cidr     = "0.0.0.0/0"
    },
    {
      protocol = "tcp"
      port     = 53
      cidr     = "${cidrhost(module.vpc.vpc_cidr_block, 2)}/32"
    },
    {
      protocol = "udp"
      port     = 53
      cidr     = "${cidrhost(module.vpc.vpc_cidr_block, 2)}/32"
    },
  ]

  sg_ingress_rules = [
    {
      protocol = "tcp"
      port     = 6443
      cidr     = module.vpc.vpc_cidr_block
    },
    {
      protocol = "tcp"
      port     = 10250
      cidr     = module.vpc.vpc_cidr_block
    },
  ]
}

resource "aws_vpc_security_group_ingress_rule" "etcd_from_control_plane" {
  security_group_id            = module.control_plane_security_group.security_group_id
  referenced_security_group_id = module.control_plane_security_group.security_group_id
  ip_protocol                  = "tcp"
  from_port                    = 2379
  to_port                      = 2380
}

resource "aws_vpc_security_group_egress_rule" "etcd_from_control_plane" {
  security_group_id            = module.control_plane_security_group.security_group_id
  referenced_security_group_id = module.control_plane_security_group.security_group_id
  ip_protocol                  = "tcp"
  from_port                    = 2379
  to_port                      = 2380
}

module "worker_security_group" {
  source = "../../modules/security-groups"

  vpc_id                     = module.vpc.vpc_id
  security_group_name        = "worker-security-group"
  security_group_description = "Security group for worker"

  sg_egress_rules = [
    {
      protocol = "tcp"
      port     = 443
      cidr     = "0.0.0.0/0"
    },
    {
      protocol = "tcp"
      port     = 6443
      cidr     = module.vpc.vpc_cidr_block
    },
    {
      protocol = "tcp"
      port     = 53
      cidr     = "${cidrhost(module.vpc.vpc_cidr_block, 2)}/32"
    },
    {
      protocol = "udp"
      port     = 53
      cidr     = "${cidrhost(module.vpc.vpc_cidr_block, 2)}/32"
    },
  ]

  sg_ingress_rules = [
    {
      protocol = "tcp"
      port     = 10250
      cidr     = module.vpc.vpc_cidr_block
    },
  ]
}
