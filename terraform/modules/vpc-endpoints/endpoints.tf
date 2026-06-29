resource "aws_vpc_endpoint" "this" {
  for_each = local.service_endpoints

  vpc_id              = var.vpc_id
  service_name        = each.value.service_name
  route_table_ids     = each.value.route_table_ids
  subnet_ids          = each.value.subnet_ids
  vpc_endpoint_type   = each.value.vpc_endpoint_type
  private_dns_enabled = each.value.vpc_endpoint_type == "Interface" ? true : false
  security_group_ids  = each.value.vpc_endpoint_type == "Interface" ? [aws_security_group.this.id] : null
}
