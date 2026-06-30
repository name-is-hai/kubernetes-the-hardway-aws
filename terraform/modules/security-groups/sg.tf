resource "aws_security_group" "this" {
  name        = var.security_group_name
  description = var.security_group_description
  vpc_id      = var.vpc_id
}

resource "aws_vpc_security_group_ingress_rule" "this" {
  for_each = {
    for index, rule in var.sg_ingress_rules :
    index => rule
  }
  security_group_id = aws_security_group.this.id
  ip_protocol       = each.value.protocol
  to_port           = each.value.port
  from_port         = each.value.port
  cidr_ipv4         = each.value.cidr
}

resource "aws_vpc_security_group_egress_rule" "this" {
  for_each = {
    for index, rule in var.sg_egress_rules :
    index => rule
  }
  security_group_id = aws_security_group.this.id
  ip_protocol       = each.value.protocol
  to_port           = each.value.port
  from_port         = each.value.port
  cidr_ipv4         = each.value.cidr
}
