resource "aws_instance" "this" {
  count = var.instance_count

  ami                  = var.ami_id
  instance_type        = var.instance_type
  iam_instance_profile = var.iam_instance_profile

  vpc_security_group_ids      = var.security_group_ids
  subnet_id                   = var.subnet_ids[count.index % length(var.subnet_ids)]
  associate_public_ip_address = false
  monitoring                  = true

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  tags = {
    Name = format("%s-%02d", var.name_prefix, count.index + 1)
    Role = var.role
  }
}
