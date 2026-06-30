variable "vpc_id" {
  type        = string
  description = "VPC Id"
}

variable "security_group_name" {
  type        = string
  description = "Security group name"
}

variable "security_group_description" {
  type        = string
  description = "Security group description"
  default     = null
}

variable "sg_egress_rules" {
  type = list(object({
    protocol = string
    port     = number
    cidr     = string
  }))
  description = "Security group egress rules"
  default     = []
}

variable "sg_ingress_rules" {
  type = list(object({
    protocol = string
    port     = number
    cidr     = string
  }))
  description = "Security group ingress rules"
  default     = []
}
