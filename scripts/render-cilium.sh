#!/usr/bin/env bash
set -euo pipefail

CILIUM_VERSION="${CILIUM_VERSION:-1.19.3}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VALUES_FILE="${ROOT_DIR}/k8s/cilium/values.yaml"
OUTPUT_FILE="${ROOT_DIR}/k8s/cilium/cilium.yaml"

if ! command -v helm >/dev/null 2>&1; then
  echo "helm is required to render Cilium manifests" >&2
  exit 1
fi

helm repo add cilium https://helm.cilium.io --force-update >/dev/null
helm repo update cilium >/dev/null

helm template cilium cilium/cilium \
  --namespace kube-system \
  --version "${CILIUM_VERSION}" \
  --values "${VALUES_FILE}" \
  > "${OUTPUT_FILE}"

echo "Rendered ${OUTPUT_FILE} with Cilium chart ${CILIUM_VERSION}"
