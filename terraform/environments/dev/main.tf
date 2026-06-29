module "vpc" {
  source               = "../../modules/vpc"
  vpc_cidr_block       = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
  public_subnets = [
    {
      cidr_block        = "10.0.1.0/24"
      availability_zone = "us-east-1a"
      name              = "public-subnet-1"
    },
    {
      cidr_block        = "10.0.2.0/24"
      availability_zone = "us-east-1b"
      name              = "public-subnet-2"
    },
    {
      cidr_block        = "10.0.3.0/24"
      availability_zone = "us-east-1c"
      name              = "public-subnet-3"
    },
  ]
  private_subnets = [
    {
      cidr_block        = "10.0.10.0/24"
      availability_zone = "us-east-1a"
      name              = "private-subnet-1"
    },
    {
      cidr_block        = "10.0.20.0/24"
      availability_zone = "us-east-1b"
      name              = "private-subnet-2"
    },
    {
      cidr_block        = "10.0.30.0/24"
      availability_zone = "us-east-1c"
      name              = "private-subnet-3"
    },
  ]
}

module "vpc_endpoints" {
  source = "../../modules/vpc-endpoints"
  vpc_id = module.vpc.vpc_id
  vpc_endpoints = [
    {
      service_name      = "com.amazonaws.${var.aws_region}.s3"
      route_table_ids   = values(module.vpc.private_route_table_ids)
      vpc_endpoint_type = "Gateway"
    },
    {
      service_name      = "com.amazonaws.${var.aws_region}.ec2messages"
      subnet_ids        = values(module.vpc.private_subnet_ids)
      vpc_endpoint_type = "Interface"
    },
    {
      service_name      = "com.amazonaws.${var.aws_region}.ssm"
      subnet_ids        = values(module.vpc.private_subnet_ids)
      vpc_endpoint_type = "Interface"
    },
    {
      service_name      = "com.amazonaws.${var.aws_region}.ssmmessages"
      subnet_ids        = values(module.vpc.private_subnet_ids)
      vpc_endpoint_type = "Interface"
    },
  ]
}
