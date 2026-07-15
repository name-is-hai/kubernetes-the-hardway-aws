variable "vpc_id" {
  type = string
}

variable "nlb_name" {
  type = string
}

variable "nlb_subnets_ids" {
  type = list(string)
}

variable "nlb_tg_port" {
  type = number
}

variable "cp_instance_ids" {
  type = list(string)
}

variable "security_group_ids" {
  type    = list(string)
  default = []
}
