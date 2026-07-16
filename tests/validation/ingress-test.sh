#!/usr/bin/env bash
set -euo pipefail

INVENTORY="${INVENTORY:-ansible/inventory/aws_ec2.yml}"
CONTROL_PLANE_HOST="${CONTROL_PLANE_HOST:-cp-01}"
WORKER_GROUP="${WORKER_GROUP:-role_worker}"
KUBECONFIG="${KUBECONFIG:-/etc/kubernetes/admin.kubeconfig}"
TERRAFORM_DIR="${TERRAFORM_DIR:-terraform/environments/dev}"
INGRESS_HOST="${INGRESS_HOST:-smoke.local}"

ansible -i "${INVENTORY}" "${CONTROL_PLANE_HOST}" -b -m shell -a "
  kubectl --kubeconfig ${KUBECONFIG} -n haproxy-ingress get pods,svc -o wide
"

ansible -i "${INVENTORY}" "${CONTROL_PLANE_HOST}" -b -m copy \
  -a "src=k8s/smoke-app/ dest=/tmp/smoke-app/ mode=0644"

ansible -i "${INVENTORY}" "${CONTROL_PLANE_HOST}" -b -m shell -a "
  kubectl --kubeconfig ${KUBECONFIG} apply \
    -f /tmp/smoke-app/namespace.yaml \
    -f /tmp/smoke-app/deployment.yaml \
    -f /tmp/smoke-app/service.yaml \
    -f /tmp/smoke-app/ingress.yaml

  kubectl --kubeconfig ${KUBECONFIG} \
    -n smoke-app rollout status deployment/smoke-app \
    --timeout=120s
"

ansible -i "${INVENTORY}" "${CONTROL_PLANE_HOST}" -b -m shell -a "
  kubectl --kubeconfig ${KUBECONFIG} -n smoke-app get pods,svc,ingress -o wide
"

ansible -i "${INVENTORY}" "${CONTROL_PLANE_HOST}" -b -m shell -a "
  NAME=ingress-test-\$(date +%s)
  HAPROXY_IP=\$(kubectl --kubeconfig ${KUBECONFIG} -n haproxy-ingress get svc haproxy-ingress-kubernetes-ingress -o jsonpath='{.spec.clusterIP}')

  kubectl --kubeconfig ${KUBECONFIG} run \"\$NAME\" \
    --image=curlimages/curl:8.10.1 \
    --restart=Never \
    -- sleep 300

  kubectl --kubeconfig ${KUBECONFIG} wait \
    --for=condition=Ready pod/\"\$NAME\" --timeout=90s

  kubectl --kubeconfig ${KUBECONFIG} exec \"\$NAME\" -- \
    curl -sS -H \"Host: ${INGRESS_HOST}\" \"http://\$HAPROXY_IP/\"

  kubectl --kubeconfig ${KUBECONFIG} delete pod \"\$NAME\"
"

ansible -i "${INVENTORY}" "${WORKER_GROUP}" -b -m shell -a "
  echo \"=== \$(hostname) ===\"
  curl -sS -H \"Host: ${INGRESS_HOST}\" http://127.0.0.1:30080/ |
  grep -o \"Welcome to nginx\" || true
"

ansible -i "${INVENTORY}" "${CONTROL_PLANE_HOST}" -b -m shell -a "
  kubectl --kubeconfig ${KUBECONFIG} -n haproxy-ingress get pods,svc -o wide
"

DNS="$(terraform -chdir="${TERRAFORM_DIR}" output -raw public_nlb_dns_name)"

curl -i -H "Host: ${INGRESS_HOST}" "http://${DNS}/"
