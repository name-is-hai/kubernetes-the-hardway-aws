#!/usr/bin/env bash
set -euo pipefail

PROJECT_TAG="${PROJECT_TAG:-k8s-hardway}"
AWS_REGION="${AWS_REGION:-us-east-1}"
STATE_BUCKET="${STATE_BUCKET:-k8s-hardway-terraform-state}"
STATE_KEY="${STATE_KEY:-dev/terraform.tfstate}"
DELETE_STATE=false
YES=false

usage() {
  cat <<EOF
Usage: $0 --yes [--delete-state]

Deletes AWS dev infrastructure tagged Project=${PROJECT_TAG}, but does not
delete AMIs or snapshots.

Options:
  --yes           Required. Confirms destructive AWS cleanup.
  --delete-state  Delete s3://${STATE_BUCKET}/${STATE_KEY} after cleanup.

Environment overrides:
  PROJECT_TAG     Default: k8s-hardway
  AWS_REGION      Default: us-east-1
  STATE_BUCKET    Default: k8s-hardway-terraform-state
  STATE_KEY       Default: dev/terraform.tfstate
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --yes)
      YES=true
      ;;
    --delete-state)
      DELETE_STATE=true
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

if [ "${YES}" != "true" ]; then
  usage >&2
  exit 2
fi

aws_ec2() {
  aws ec2 --region "${AWS_REGION}" "$@"
}

aws_elbv2() {
  aws elbv2 --region "${AWS_REGION}" "$@"
}

aws_s3api() {
  aws s3api --region "${AWS_REGION}" "$@"
}

aws_iam() {
  aws iam "$@"
}

log() {
  printf '\n==> %s\n' "$*"
}

ids_or_empty() {
  tr '\t' '\n' | sed '/^None$/d;/^$/d'
}

log "Using AWS account"
aws sts get-caller-identity --output table

log "Finding VPCs tagged Project=${PROJECT_TAG}"
mapfile -t VPC_IDS < <(
  aws_ec2 describe-vpcs \
    --filters "Name=tag:Project,Values=${PROJECT_TAG}" \
    --query 'Vpcs[].VpcId' \
    --output text | ids_or_empty
)

if [ "${#VPC_IDS[@]}" -eq 0 ]; then
  log "No tagged VPCs found"
else
  printf '%s\n' "${VPC_IDS[@]}"
fi

log "Terminating tagged EC2 instances"
mapfile -t INSTANCE_IDS < <(
  aws_ec2 describe-instances \
    --filters "Name=tag:Project,Values=${PROJECT_TAG}" "Name=instance-state-name,Values=pending,running,stopping,stopped,shutting-down" \
    --query 'Reservations[].Instances[].InstanceId' \
    --output text | ids_or_empty
)

if [ "${#INSTANCE_IDS[@]}" -gt 0 ]; then
  aws_ec2 terminate-instances --instance-ids "${INSTANCE_IDS[@]}" >/dev/null
  aws_ec2 wait instance-terminated --instance-ids "${INSTANCE_IDS[@]}"
else
  log "No active tagged EC2 instances found"
fi

for vpc_id in "${VPC_IDS[@]}"; do
  log "Cleaning VPC ${vpc_id}"

  log "Deleting load balancers in ${vpc_id}"
  mapfile -t LB_ARNS < <(
    aws_elbv2 describe-load-balancers \
      --query "LoadBalancers[?VpcId=='${vpc_id}'].LoadBalancerArn" \
      --output text | ids_or_empty
  )
  if [ "${#LB_ARNS[@]}" -gt 0 ]; then
    for lb_arn in "${LB_ARNS[@]}"; do
      aws_elbv2 delete-load-balancer --load-balancer-arn "${lb_arn}"
    done
    aws_elbv2 wait load-balancers-deleted --load-balancer-arns "${LB_ARNS[@]}"
  fi

  log "Deleting target groups in ${vpc_id}"
  mapfile -t TG_ARNS < <(
    aws_elbv2 describe-target-groups \
      --query "TargetGroups[?VpcId=='${vpc_id}'].TargetGroupArn" \
      --output text | ids_or_empty
  )
  for tg_arn in "${TG_ARNS[@]}"; do
    aws_elbv2 delete-target-group --target-group-arn "${tg_arn}" || true
  done

  log "Deleting VPC endpoints in ${vpc_id}"
  mapfile -t VPCE_IDS < <(
    aws_ec2 describe-vpc-endpoints \
      --filters "Name=vpc-id,Values=${vpc_id}" \
      --query 'VpcEndpoints[].VpcEndpointId' \
      --output text | ids_or_empty
  )
  if [ "${#VPCE_IDS[@]}" -gt 0 ]; then
    aws_ec2 delete-vpc-endpoints --vpc-endpoint-ids "${VPCE_IDS[@]}" >/dev/null
  fi

  log "Deleting NAT gateways in ${vpc_id}"
  mapfile -t NAT_IDS < <(
    aws_ec2 describe-nat-gateways \
      --filter "Name=vpc-id,Values=${vpc_id}" "Name=state,Values=pending,available,deleting" \
      --query 'NatGateways[].NatGatewayId' \
      --output text | ids_or_empty
  )
  mapfile -t NAT_EIP_ALLOCS < <(
    aws_ec2 describe-nat-gateways \
      --filter "Name=vpc-id,Values=${vpc_id}" \
      --query 'NatGateways[].NatGatewayAddresses[].AllocationId' \
      --output text | ids_or_empty
  )
  for nat_id in "${NAT_IDS[@]}"; do
    aws_ec2 delete-nat-gateway --nat-gateway-id "${nat_id}" >/dev/null || true
  done
  for nat_id in "${NAT_IDS[@]}"; do
    aws_ec2 wait nat-gateway-deleted --nat-gateway-ids "${nat_id}" || true
  done
  for allocation_id in "${NAT_EIP_ALLOCS[@]}"; do
    aws_ec2 release-address --allocation-id "${allocation_id}" || true
  done

  log "Waiting for endpoint/network interfaces to disappear in ${vpc_id}"
  for _ in $(seq 1 30); do
    eni_count="$(
      aws_ec2 describe-network-interfaces \
        --filters "Name=vpc-id,Values=${vpc_id}" \
        --query 'length(NetworkInterfaces)' \
        --output text
    )"
    if [ "${eni_count}" = "0" ]; then
      break
    fi
    sleep 10
  done

  log "Deleting non-default security groups in ${vpc_id}"
  for _ in $(seq 1 5); do
    mapfile -t SG_IDS < <(
      aws_ec2 describe-security-groups \
        --filters "Name=vpc-id,Values=${vpc_id}" \
        --query "SecurityGroups[?GroupName!='default'].GroupId" \
        --output text | ids_or_empty
    )
    [ "${#SG_IDS[@]}" -eq 0 ] && break
    for sg_id in "${SG_IDS[@]}"; do
      aws_ec2 delete-security-group --group-id "${sg_id}" || true
    done
    sleep 5
  done

  log "Deleting subnets in ${vpc_id}"
  mapfile -t SUBNET_IDS < <(
    aws_ec2 describe-subnets \
      --filters "Name=vpc-id,Values=${vpc_id}" \
      --query 'Subnets[].SubnetId' \
      --output text | ids_or_empty
  )
  for subnet_id in "${SUBNET_IDS[@]}"; do
    aws_ec2 delete-subnet --subnet-id "${subnet_id}" || true
  done

  log "Deleting custom route tables in ${vpc_id}"
  mapfile -t RTB_IDS < <(
    aws_ec2 describe-route-tables \
      --filters "Name=vpc-id,Values=${vpc_id}" \
      --query 'RouteTables[?!Associations[?Main==`true`]].RouteTableId' \
      --output text | ids_or_empty
  )
  for rtb_id in "${RTB_IDS[@]}"; do
    aws_ec2 delete-route-table --route-table-id "${rtb_id}" || true
  done

  log "Deleting custom network ACLs in ${vpc_id}"
  mapfile -t NACL_IDS < <(
    aws_ec2 describe-network-acls \
      --filters "Name=vpc-id,Values=${vpc_id}" \
      --query 'NetworkAcls[?IsDefault==`false`].NetworkAclId' \
      --output text | ids_or_empty
  )
  for nacl_id in "${NACL_IDS[@]}"; do
    aws_ec2 delete-network-acl --network-acl-id "${nacl_id}" || true
  done

  log "Detaching and deleting internet gateways in ${vpc_id}"
  mapfile -t IGW_IDS < <(
    aws_ec2 describe-internet-gateways \
      --filters "Name=attachment.vpc-id,Values=${vpc_id}" \
      --query 'InternetGateways[].InternetGatewayId' \
      --output text | ids_or_empty
  )
  for igw_id in "${IGW_IDS[@]}"; do
    aws_ec2 detach-internet-gateway --internet-gateway-id "${igw_id}" --vpc-id "${vpc_id}" || true
    aws_ec2 delete-internet-gateway --internet-gateway-id "${igw_id}" || true
  done

  log "Deleting VPC ${vpc_id}"
  aws_ec2 delete-vpc --vpc-id "${vpc_id}" || true
done

log "Deleting known lab IAM instance profiles and roles"
for profile in \
  packer-ssm-instance-profile \
  control-plane-ssm-instance-profile \
  worker-ssm-instance-profile \
  ec2-ssm-instance-profile
do
  mapfile -t role_names < <(
    aws_iam get-instance-profile \
      --instance-profile-name "${profile}" \
      --query 'InstanceProfile.Roles[].RoleName' \
      --output text 2>/dev/null | ids_or_empty
  )
  for role_name in "${role_names[@]}"; do
    aws_iam remove-role-from-instance-profile \
      --instance-profile-name "${profile}" \
      --role-name "${role_name}" || true
  done
  aws_iam delete-instance-profile --instance-profile-name "${profile}" || true
done

for role in \
  packer-ssm-execution-role \
  control-plane-ssm-execution-role \
  worker-ssm-execution-role \
  ec2-ssm-execution-role
do
  aws_iam detach-role-policy \
    --role-name "${role}" \
    --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore || true
  aws_iam delete-role --role-name "${role}" || true
done

if [ "${DELETE_STATE}" = "true" ]; then
  log "Deleting Terraform state object s3://${STATE_BUCKET}/${STATE_KEY}"
  aws_s3api delete-object --bucket "${STATE_BUCKET}" --key "${STATE_KEY}" >/dev/null || true
fi

log "Final verification"
aws_ec2 describe-vpcs \
  --filters "Name=tag:Project,Values=${PROJECT_TAG}" \
  --query 'Vpcs[].VpcId' \
  --output text
aws_ec2 describe-instances \
  --filters "Name=tag:Project,Values=${PROJECT_TAG}" "Name=instance-state-name,Values=pending,running,stopping,stopped,shutting-down" \
  --query 'Reservations[].Instances[].InstanceId' \
  --output text
aws_ec2 describe-images \
  --owners self \
  --filters "Name=name,Values=k8s-*" \
  --query 'Images[].{ImageId:ImageId,Name:Name,State:State}' \
  --output table

log "Cleanup complete. AMIs were not deleted."
