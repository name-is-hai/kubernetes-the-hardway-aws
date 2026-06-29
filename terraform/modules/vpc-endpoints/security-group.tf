resource "aws_security_group" "this" {
  name        = "vpc-endpoints-sg"
  description = "Security group for VPC endpoints"
  vpc_id      = data.aws_vpc.selected.id
}

resource "aws_vpc_security_group_ingress_rule" "this" {
  security_group_id = aws_security_group.this.id
  ip_protocol       = "tcp"
  to_port           = 443
  from_port         = 443
  cidr_ipv4         = data.aws_vpc.selected.cidr_block
}
