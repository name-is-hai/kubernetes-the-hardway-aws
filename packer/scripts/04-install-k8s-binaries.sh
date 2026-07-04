#!/usr/bin/env bash
set -euo pipefail

: "${KUBERNETES_VERSION:?KUBERNETES_VERSION is required}"

ROLE="${1:?usage: install-k8s-binaries.sh <control-plane|worker>}"

case "${ROLE}" in
  control-plane)
    BINARIES=(
      kube-apiserver
      kube-controller-manager
      kube-scheduler
      kubectl
      kubelet
    )
    ;;
  worker)
    BINARIES=(
      kubectl
      kubelet
      kube-proxy
    )
    ;;
  *)
    echo "unknown role: ${ROLE}" >&2
    exit 1
    ;;
esac

ARCH="$(uname -m)"
case "${ARCH}" in
  x86_64) ARCH="amd64" ;;
  aarch64) ARCH="arm64" ;;
  *)
    echo "unsupported architecture: ${ARCH}" >&2
    exit 1
    ;;
esac

WORKDIR="/tmp/kubernetes-binaries"
rm -rf "${WORKDIR}"
mkdir -p "${WORKDIR}"
cd "${WORKDIR}"

for binary in "${BINARIES[@]}"; do
  url="https://dl.k8s.io/release/v${KUBERNETES_VERSION}/bin/linux/${ARCH}/${binary}"
  wget -q --show-progress --https-only --timestamping "${url}"
  sudo install -m 0755 "${binary}" "/usr/local/bin/${binary}"
done

for binary in "${BINARIES[@]}"; do
  case "${binary}" in
    kubectl)
      kubectl version --client
      ;;
    *)
      "${binary}" --version
      ;;
  esac
done

cd /
rm -rf "${WORKDIR}"
