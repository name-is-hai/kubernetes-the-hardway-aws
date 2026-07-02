variable "ami_id" {
  type        = string
  description = "AMI ID used to launch the EC2 instances."
}

variable "instance_type" {
  type        = string
  description = "EC2 instance type used for the instances."
}

variable "subnet_ids" {
  type        = list(string)
  description = "Subnet IDs where the instances are launched."
  validation {
    error_message = "Subnet ids must not empty"
    condition     = length(var.subnet_ids) > 0
  }
}

variable "security_group_ids" {
  type        = list(string)
  description = "Security group IDs attached to each instance."
}

variable "instance_count" {
  type        = number
  description = "Number of EC2 instances to create."
}

variable "iam_instance_profile" {
  type        = string
  description = "IAM instance profile name attached to each instance."
}

variable "name_prefix" {
  type        = string
  description = "Prefix used for instance Name tags, such as cp or worker."
}

variable "role" {
  type        = string
  description = "Node role tag value, such as control-plane or worker."
}
