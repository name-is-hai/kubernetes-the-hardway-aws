locals {
  public_subnets_by_name = {
    for subnet in var.public_subnets : subnet.name => subnet
  }
  private_subnets_by_name = {
    for subnet in var.private_subnets : subnet.name => subnet
  }
  nat_availability_zones = distinct([
    for subnet in var.private_subnets :
    subnet.availability_zone
  ])
}
