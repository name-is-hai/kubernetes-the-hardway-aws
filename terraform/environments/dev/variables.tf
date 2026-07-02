variable "aws_region" {
  description = "AWS region where the lab infrastructure is created."
  default     = "us-east-1"
  type        = string
}

variable "ami_control_plane_id" {
  description = "AMI ID built by Packer for Kubernetes control-plane EC2 instances."
  type        = string
}

variable "ami_worker_id" {
  description = "AMI ID built by Packer for Kubernetes worker EC2 instances."
  type        = string
}
