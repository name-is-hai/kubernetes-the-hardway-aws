#!/usr/bin/env bash
set -euo pipefail

AWS_REGION="${AWS_REGION:-us-east-1}"
TF_DIR="${TF_DIR:-terraform/environments/dev}"
ANSIBLE_CONFIG="${ANSIBLE_CONFIG:-ansible/ansible.cfg}"
ANSIBLE_INVENTORY="${ANSIBLE_INVENTORY:-ansible/inventory/aws_ec2.yml}"
SKIP_TERRAFORM="${SKIP_TERRAFORM:-false}"
SKIP_ANSIBLE_COMMON="${SKIP_ANSIBLE_COMMON:-false}"
SKIP_LOCAL_CERT_CLEANUP="${SKIP_LOCAL_CERT_CLEANUP:-false}"

export AWS_REGION
export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-$AWS_REGION}"
export ANSIBLE_CONFIG
export ANSIBLE_LOCAL_TEMP="${ANSIBLE_LOCAL_TEMP:-/tmp/ansible-local}"

log() {
  printf '\n==> %s\n' "$*"
}

usage() {
  cat <<EOF
Usage: $0

Runs the lab workflow through the current completed phase:
  1. Verify AWS identity
  2. Terraform init/apply
  3. Wait for six SSM-managed nodes
  4. Run Ansible wait/common setup

Environment overrides:
  AWS_REGION             Default: us-east-1
  TF_DIR                 Default: terraform/environments/dev
  ANSIBLE_CONFIG         Default: ansible/ansible.cfg
  ANSIBLE_INVENTORY      Default: ansible/inventory/aws_ec2.yml
  SKIP_TERRAFORM         Default: false
  SKIP_ANSIBLE_COMMON    Default: false
  SKIP_LOCAL_CERT_CLEANUP Default: false

Terraform AMI variables can be supplied by terraform.tfvars or TF_VAR_*:
  TF_VAR_ami_control_plane_id=ami-...
  TF_VAR_ami_worker_id=ami-...
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage
  exit 0
fi

terraform_output_raw() {
  terraform -chdir="${TF_DIR}" output -raw "$1" 2>/dev/null || true
}

log "Using AWS identity"
aws sts get-caller-identity --output table

if [ "${SKIP_TERRAFORM}" != "true" ]; then
  log "Terraform init"
  terraform -chdir="${TF_DIR}" init

  log "Terraform apply"
  terraform -chdir="${TF_DIR}" apply

  log "Terraform outputs"
  terraform -chdir="${TF_DIR}" output
else
  log "Skipping Terraform"
fi

if [ "${SKIP_ANSIBLE_COMMON}" != "true" ]; then
  if [ "${SKIP_LOCAL_CERT_CLEANUP}" != "true" ]; then
    log "Cleaning local generated certs/kubeconfigs"
    rm -rf ansible/generated/pki ansible/generated/kubeconfigs
  else
    log "Skipping local generated cert cleanup"
  fi

  log "Checking Ansible inventory"
  ansible-inventory -i "${ANSIBLE_INVENTORY}" --graph

  API_NLB_DNS_NAME="${API_NLB_DNS_NAME:-$(terraform_output_raw api_nlb_dns_name)}"

 if [ -n "${API_NLB_DNS_NAME}" ]; then
    log "Running Phase 4 wait/common playbooks"
    ansible-playbook -i ansible/inventory/aws_ec2.yml ansible/site.yml -e "api_nlb_dns_name=${API_NLB_DNS_NAME}"
  else
    log "Running Phase 4 need to have api_nlb_dns_name from Terraform output vars"
    exit 1
  fi
 else
  log "Skipping Ansible common setup"
fi

log "Up workflow complete through current phase"
