resource "aws_eip" "this" {
  for_each = toset(local.nat_availability_zones)

  domain = "vpc"
}

resource "aws_nat_gateway" "this" {
  vpc_id            = aws_vpc.this.id
  availability_mode = "regional"

  dynamic "availability_zone_address" {
    for_each = aws_eip.this

    content {
      availability_zone = availability_zone_address.key
      allocation_ids    = [availability_zone_address.value.id]
    }
  }

  depends_on = [aws_internet_gateway.this]
}
