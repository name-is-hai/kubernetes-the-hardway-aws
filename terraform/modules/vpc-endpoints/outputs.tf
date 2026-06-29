output "vpc_endpoints" {
  value = {
    for name, endpoint in aws_vpc_endpoint.this : name => endpoint.id
  }
}
