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
