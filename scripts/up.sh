#!/usr/bin/env bash
set -euo pipefail

AWS_REGION="${AWS_REGION:-us-east-1}"
TF_DIR="${TF_DIR:-terraform/environments/dev}"
ANSIBLE_CONFIG="${ANSIBLE_CONFIG:-ansible/ansible.cfg}"
ANSIBLE_INVENTORY="${ANSIBLE_INVENTORY:-ansible/inventory/aws_ec2.yml}"
CP_AMI_ID="${CP_AMI_ID:-${CONTROL_PLANE_AMI_ID:-${TF_VAR_ami_control_plane_id:-}}}"
WORKER_AMI_ID="${WORKER_AMI_ID:-${TF_VAR_ami_worker_id:-}}"
SKIP_TERRAFORM="${SKIP_TERRAFORM:-false}"
SKIP_ANSIBLE_COMMON="${SKIP_ANSIBLE_COMMON:-false}"
SKIP_LOCAL_CERT_CLEANUP="${SKIP_LOCAL_CERT_CLEANUP:-false}"

export AWS_REGION
export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-$AWS_REGION}"
export ANSIBLE_CONFIG
export ANSIBLE_LOCAL_TEMP="${ANSIBLE_LOCAL_TEMP:-/tmp/ansible-local}"

if [ -n "${CP_AMI_ID}" ]; then
  export TF_VAR_ami_control_plane_id="${CP_AMI_ID}"
fi

if [ -n "${WORKER_AMI_ID}" ]; then
  export TF_VAR_ami_worker_id="${WORKER_AMI_ID}"
fi

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
  CP_AMI_ID              Control-plane AMI ID passed to Terraform
  WORKER_AMI_ID          Worker AMI ID passed to Terraform
  SKIP_TERRAFORM         Default: false
  SKIP_ANSIBLE_COMMON    Default: false
  SKIP_LOCAL_CERT_CLEANUP Default: false

Terraform AMI variables can be supplied by terraform.tfvars or TF_VAR_*:
  TF_VAR_ami_control_plane_id=ami-...
  TF_VAR_ami_worker_id=ami-...

Example:
  CP_AMI_ID=ami-... WORKER_AMI_ID=ami-... $0
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage
  exit 0
fi

terraform_output_raw() {
  terraform -chdir="${TF_DIR}" output -raw "$1" 2>/dev/null || true
}

terraform_var_defined() {
  local var_name="$1"
  local env_name="TF_VAR_${var_name}"

  if [ -n "${!env_name:-}" ]; then
    return 0
  fi

  local restore_nullglob
  restore_nullglob="$(shopt -p nullglob || true)"
  shopt -s nullglob
  local tfvars_files=("${TF_DIR}"/*.tfvars "${TF_DIR}"/*.auto.tfvars)
  eval "${restore_nullglob}"

  if [ "${#tfvars_files[@]}" -eq 0 ]; then
    return 1
  fi

  rg -q "^[[:space:]]*${var_name}[[:space:]]*=" "${tfvars_files[@]}"
}

require_terraform_ami_vars() {
  local missing_vars=()

  if ! terraform_var_defined "ami_control_plane_id"; then
    missing_vars+=("ami_control_plane_id")
  fi

  if ! terraform_var_defined "ami_worker_id"; then
    missing_vars+=("ami_worker_id")
  fi

  if [ "${#missing_vars[@]}" -gt 0 ]; then
    printf 'Missing Terraform AMI variable(s): %s\n' "${missing_vars[*]}" >&2
    printf '\nSet them with either:\n' >&2
    printf '  CP_AMI_ID=ami-... WORKER_AMI_ID=ami-... %s\n' "$0" >&2
    printf '\nOr put them in %s/terraform.tfvars:\n' "${TF_DIR}" >&2
    printf '  ami_control_plane_id = "ami-..."\n' >&2
    printf '  ami_worker_id        = "ami-..."\n' >&2
    exit 1
  fi
}

log "Using AWS identity"
aws sts get-caller-identity --output table

if [ "${SKIP_TERRAFORM}" != "true" ]; then
  require_terraform_ami_vars

  log "Terraform init"
  terraform -chdir="${TF_DIR}" init

  log "Terraform apply"
  terraform -chdir="${TF_DIR}" apply -auto-approve

  log "Terraform outputs"
  terraform -chdir="${TF_DIR}" output
else
  log "Skipping Terraform"
fi

if [ "${SKIP_ANSIBLE_COMMON}" != "true" ]; then
  if [ "${SKIP_LOCAL_CERT_CLEANUP}" != "true" ]; then
    log "Cleaning local generated certs/kubeconfigs"
    rm -rf ansible/generated/
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
