variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "aws_vpc_id" {
  type = string
}

variable "aws_subnet_id" {
  type = string
}

variable "aws_security_group_id" {
  type = string
}

variable "iam_instance_profile" {
  type = string
}

variable "builder_instance_type" {
  type = string
}

variable "source_ami_id" {
  type = string
}

variable "kubernetes_version" {
  type = string
}

variable "containerd_version" {
  type = string
}

variable "runc_version" {
  type = string
}
variable "crictl_version" {
  type = string
}
variable "cni_plugins_version" {
  type = string
}

variable "etcd_version" {
  type = string
}

variable "helm_version" {
  type = string
}
