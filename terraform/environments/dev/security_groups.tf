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
    {
      protocol = "tcp"
      port     = 6443
      cidr     = module.vpc.vpc_cidr_block
    },
  ]

  sg_ingress_rules = [
    {
      protocol = "tcp"
      port     = 6443
      cidr     = module.vpc.vpc_cidr_block
    },
  ]
}

module "public_nlb_security_group" {
  source = "../../modules/security-groups"

  vpc_id                     = module.vpc.vpc_id
  security_group_name        = "public-nlb-security-group"
  security_group_description = "Security group for public NLB"

  sg_ingress_rules = [
    {
      protocol = "tcp"
      port     = 443
      cidr     = "0.0.0.0/0"
    },
    {
      protocol = "tcp"
      port     = 80
      cidr     = "0.0.0.0/0"
    },
  ]
}

resource "aws_vpc_security_group_egress_rule" "public_http_nlb_to_worker" {
  security_group_id            = module.public_nlb_security_group.security_group_id
  referenced_security_group_id = module.worker_security_group.security_group_id
  ip_protocol                  = "tcp"
  from_port                    = 30080
  to_port                      = 30080
}

resource "aws_vpc_security_group_egress_rule" "public_https_nlb_to_worker" {
  security_group_id            = module.public_nlb_security_group.security_group_id
  referenced_security_group_id = module.worker_security_group.security_group_id
  ip_protocol                  = "tcp"
  from_port                    = 30443
  to_port                      = 30443
}

resource "aws_vpc_security_group_ingress_rule" "worker_from_public_http_nlb" {
  security_group_id            = module.worker_security_group.security_group_id
  referenced_security_group_id = module.public_nlb_security_group.security_group_id
  ip_protocol                  = "tcp"
  from_port                    = 30080
  to_port                      = 30080
}

resource "aws_vpc_security_group_ingress_rule" "worker_from_public_https_nlb" {
  security_group_id            = module.worker_security_group.security_group_id
  referenced_security_group_id = module.public_nlb_security_group.security_group_id
  ip_protocol                  = "tcp"
  from_port                    = 30443
  to_port                      = 30443
}

module "api_nlb_security_group" {
  source = "../../modules/security-groups"

  vpc_id                     = module.vpc.vpc_id
  security_group_name        = "api-nlb-security-group"
  security_group_description = "Security group for Kubernetes API NLB"

  sg_ingress_rules = [
    {
      protocol = "tcp"
      port     = 6443
      cidr     = module.vpc.vpc_cidr_block
    },
  ]
}

resource "aws_vpc_security_group_egress_rule" "api_nlb_to_control_plane" {
  security_group_id            = module.api_nlb_security_group.security_group_id
  referenced_security_group_id = module.control_plane_security_group.security_group_id
  ip_protocol                  = "tcp"
  from_port                    = 6443
  to_port                      = 6443
}

resource "aws_vpc_security_group_ingress_rule" "control_plane_api_from_nlb" {
  security_group_id            = module.control_plane_security_group.security_group_id
  referenced_security_group_id = module.api_nlb_security_group.security_group_id
  ip_protocol                  = "tcp"
  from_port                    = 6443
  to_port                      = 6443
}

resource "aws_vpc_security_group_ingress_rule" "etcd_from_control_plane" {
  security_group_id            = module.control_plane_security_group.security_group_id
  referenced_security_group_id = module.control_plane_security_group.security_group_id
  ip_protocol                  = "tcp"
  from_port                    = 2379
  to_port                      = 2380
}

resource "aws_vpc_security_group_egress_rule" "control_plane_to_etcd" {
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
}

resource "aws_vpc_security_group_ingress_rule" "kubelet_worker_from_control_plane" {
  security_group_id            = module.worker_security_group.security_group_id
  referenced_security_group_id = module.control_plane_security_group.security_group_id
  ip_protocol                  = "tcp"
  from_port                    = 10250
  to_port                      = 10250
}

resource "aws_vpc_security_group_egress_rule" "control_plane_to_kubelet_worker" {
  security_group_id            = module.control_plane_security_group.security_group_id
  referenced_security_group_id = module.worker_security_group.security_group_id
  ip_protocol                  = "tcp"
  from_port                    = 10250
  to_port                      = 10250
}

resource "aws_vpc_security_group_ingress_rule" "worker_to_worker_vxlan" {
  security_group_id            = module.worker_security_group.security_group_id
  referenced_security_group_id = module.worker_security_group.security_group_id
  ip_protocol                  = "udp"
  from_port                    = 8472
  to_port                      = 8472
}

resource "aws_vpc_security_group_egress_rule" "worker_to_worker_vxlan" {
  security_group_id            = module.worker_security_group.security_group_id
  referenced_security_group_id = module.worker_security_group.security_group_id
  ip_protocol                  = "udp"
  from_port                    = 8472
  to_port                      = 8472
}
