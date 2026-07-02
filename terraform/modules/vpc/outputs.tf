output "vpc_id" {
  value = aws_vpc.this.id
}

output "vpc_cidr_block" {
  value = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  value = {
    for name, subnet in aws_subnet.public : name => subnet.id
  }
}

output "private_subnet_ids" {
  value = {
    for name, subnet in aws_subnet.private : name => subnet.id
  }
}

output "public_route_table_id" {
  value = aws_route_table.public.id
}

output "private_route_table_ids" {
  value = {
    for name, route_table in aws_route_table.private : name =>
    route_table.id
  }
}

output "internet_gateway_id" {
  value = aws_internet_gateway.this.id
}

output "nat_gateway_id" {
  value = aws_nat_gateway.this.id
}
