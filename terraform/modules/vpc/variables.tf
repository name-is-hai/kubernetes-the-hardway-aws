variable "vpc_cidr_block" {
  type        = string
  description = "CIDR block for the VPC"
}

variable "enable_dns_hostnames" {
  type        = bool
  description = "Enable DNS hostnames for the VPC"
}

variable "enable_dns_support" {
  type        = bool
  description = "Enable DNS support for the VPC"
}

variable "public_subnets" {
  description = "Public subnets definitions"
  type = list(object({
    cidr_block              = string
    availability_zone       = string
    name                    = string
    map_public_ip_on_launch = optional(bool, true)
  }))

  validation {
    condition     = length(var.public_subnets) > 0
    error_message = "public_subnets must not be empty"
  }
  validation {
    condition     = length(distinct([for subnet in var.public_subnets : subnet.name])) == length(var.public_subnets)
    error_message = "public_subnets names must be unique"
  }
  validation {
    condition     = length(var.public_subnets) == length(distinct([for subnet in var.public_subnets : subnet.availability_zone]))
    error_message = "public_subnets must contain at least one subnet per availability zone"
  }
}

variable "private_subnets" {
  description = "Private subnets definitions"
  type = list(object({
    cidr_block        = string
    availability_zone = string
    name              = string
  }))

  validation {
    condition     = length(var.private_subnets) > 0
    error_message = "private_subnets must not be empty"
  }
  validation {
    condition     = length(distinct([for subnet in var.private_subnets : subnet.name])) == length(var.private_subnets)
    error_message = "private_subnets names must be unique"
  }
  validation {
    condition = length(setsubtract(
      toset([for subnet in var.private_subnets : subnet.availability_zone]),
      toset([for subnet in var.public_subnets : subnet.availability_zone])
    )) == 0
    error_message = "Every private subnet availability zone must have a matching public subnet availability zone for NAT routing."
  }
}
