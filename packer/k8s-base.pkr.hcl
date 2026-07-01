packer {
  required_plugins {
    amazon = {
      version = ">= 1.2.8"
      source  = "github.com/hashicorp/amazon"
    }
  }
}

locals {
  timestamp = regex_replace(timestamp(), "[- TZ:]", "")
}

source "amazon-ebs" "control-plane" {
  region = var.aws_region

  ami_name        = "k8s-control-plane-${local.timestamp}"
  ami_description = "Kubernetes hard-way control-plane AMI"

  instance_type = var.builder_instance_type
  source_ami    = var.source_ami_id

  vpc_id            = var.aws_vpc_id
  subnet_id         = var.aws_subnet_id
  security_group_id = var.aws_security_group_id

  iam_instance_profile        = var.iam_instance_profile
  associate_public_ip_address = false

  ssh_username  = "ec2-user"
  ssh_interface = "session_manager"
}

source "amazon-ebs" "worker" {
  region = var.aws_region

  ami_name        = "k8s-worker-${local.timestamp}"
  ami_description = "Kubernetes hard-way worker AMI"

  instance_type = var.builder_instance_type
  source_ami    = var.source_ami_id

  vpc_id            = var.aws_vpc_id
  subnet_id         = var.aws_subnet_id
  security_group_id = var.aws_security_group_id

  iam_instance_profile        = var.iam_instance_profile
  associate_public_ip_address = false

  ssh_username  = "ec2-user"
  ssh_interface = "session_manager"
}

build {
  name    = "k8s-control-plane"
  sources = ["source.amazon-ebs.control-plane"]

  provisioner "shell" {
    script = "packer/scripts/01-install-base.sh"
  }

  provisioner "shell" {
    script = "packer/scripts/02-install-ssm-agent.sh"
  }

  provisioner "shell" {
    script = "packer/scripts/03-install-containerd.sh"

    environment_vars = [
      "CONTAINERD_VERSION=${var.containerd_version}",
      "RUNC_VERSION=${var.runc_version}",
      "CRICTL_VERSION=${var.crictl_version}",
    ]
  }

  provisioner "shell" {
    script = "packer/scripts/04-install-k8s-binaries.sh"

    environment_vars = [
      "KUBERNETES_VERSION=${var.kubernetes_version}",
    ]

    execute_command = "chmod +x {{ .Path }}; sudo -E {{ .Vars }} {{ .Path }} control-plane"
  }

  provisioner "shell" {
    script = "packer/scripts/05-install-etcd.sh"

    environment_vars = [
      "ETCD_VERSION=${var.etcd_version}",
    ]
  }

  provisioner "shell" {
    script = "packer/scripts/06-install-cni-tools.sh"

    environment_vars = [
      "CNI_PLUGINS_VERSION=${var.cni_plugins_version}",
    ]
  }

  provisioner "shell" {
    script          = "packer/scripts/07-finalize-ami.sh"
    execute_command = "chmod +x {{ .Path }}; sudo -E {{ .Vars }} {{ .Path }} control-plane"
  }
}

build {
  name    = "k8s-worker"
  sources = ["source.amazon-ebs.worker"]

  provisioner "shell" {
    script = "packer/scripts/01-install-base.sh"
  }

  provisioner "shell" {
    script = "packer/scripts/02-install-ssm-agent.sh"
  }

  provisioner "shell" {
    script = "packer/scripts/03-install-containerd.sh"

    environment_vars = [
      "CONTAINERD_VERSION=${var.containerd_version}",
      "RUNC_VERSION=${var.runc_version}",
      "CRICTL_VERSION=${var.crictl_version}",
    ]
  }

  provisioner "shell" {
    script = "packer/scripts/04-install-k8s-binaries.sh"

    environment_vars = [
      "KUBERNETES_VERSION=${var.kubernetes_version}",
    ]

    execute_command = "chmod +x {{ .Path }}; sudo -E {{ .Vars }} {{ .Path }} worker"
  }

  provisioner "shell" {
    script = "packer/scripts/06-install-cni-tools.sh"

    environment_vars = [
      "CNI_PLUGINS_VERSION=${var.cni_plugins_version}",
    ]
  }

  provisioner "shell" {
    script          = "packer/scripts/07-finalize-ami.sh"
    execute_command = "chmod +x {{ .Path }}; sudo -E {{ .Vars }} {{ .Path }} worker"
  }
}
