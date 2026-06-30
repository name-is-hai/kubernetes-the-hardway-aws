module "security_group" {
  source                     = "../security-groups"
  vpc_id                     = var.vpc_id
  security_group_name        = "vpc-endpoints-sg"
  security_group_description = "Security group for VPC endpoints"
  sg_ingress_rules = [
    {
      protocol = "tcp"
      port     = 443
      cidr     = data.aws_vpc.selected.cidr_block
    },
  ]
}
