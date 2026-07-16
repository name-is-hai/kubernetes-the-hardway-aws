#!/usr/bin/env bash
set -euo pipefail

HAPROXY_VERSION="${HAPROXY_VERSION:-1.52.1}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VALUES_FILE="${ROOT_DIR}/k8s/haproxy-ingress/values.yaml"
OUTPUT_FILE="${ROOT_DIR}/k8s/haproxy-ingress/haproxy-ingress.yaml"

if ! command -v helm >/dev/null 2>&1; then
  echo "helm is required to render HAProxy manifests" >&2
  exit 1
fi

helm repo add haproxy-ingress https://helm.cilium.io --force-update >/dev/null
helm repo update cilium >/dev/null
helm template haproxy-ingress haproxytech/kubernetes-ingress \
  --namespace haproxy-ingress \
  --version "${HAPROXY_VERSION}" \
  -f "${VALUES_FILE}" \
  > "${OUTPUT_FILE}"

echo "Rendered ${OUTPUT_FILE} with HAProxy chart ${HAPROXY_VERSION}"
