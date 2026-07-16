#!/usr/bin/env bash
set -euo pipefail

INVENTORY="${INVENTORY:-ansible/inventory/aws_ec2.yml}"
CONTROL_PLANE_HOST="${CONTROL_PLANE_HOST:-cp-01}"
KUBECONFIG_PATH="${KUBECONFIG_PATH:-/etc/kubernetes/admin.kubeconfig}"
DNS_IMAGE="${DNS_IMAGE:-busybox:1.36}"
EXTERNAL_DNS_NAME="${EXTERNAL_DNS_NAME:-registry.k8s.io}"

ansible -i "${INVENTORY}" "${CONTROL_PLANE_HOST}" -b -m shell -a "
  set -eu

  NAME=\"dns-test-\$(date +%s)\"

  cleanup() {
    kubectl --kubeconfig '${KUBECONFIG_PATH}' delete pod \"\${NAME}\" --ignore-not-found=true >/dev/null 2>&1 || true
  }
  trap cleanup EXIT

  kubectl --kubeconfig '${KUBECONFIG_PATH}' run \"\${NAME}\" \
    --image='${DNS_IMAGE}' \
    --restart=Never \
    -- sleep 300

  kubectl --kubeconfig '${KUBECONFIG_PATH}' wait \
    --for=condition=Ready \"pod/\${NAME}\" \
    --timeout=90s

  echo '--- cluster DNS ---'
  kubectl --kubeconfig '${KUBECONFIG_PATH}' exec \"\${NAME}\" -- \
    nslookup kubernetes.default.svc.cluster.local

  echo '--- external DNS ---'
  kubectl --kubeconfig '${KUBECONFIG_PATH}' exec \"\${NAME}\" -- \
    nslookup '${EXTERNAL_DNS_NAME}'
"
