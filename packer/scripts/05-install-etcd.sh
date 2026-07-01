#!/usr/bin/env bash
set -euo pipefail

: "${ETCD_VERSION:?ETCD_VERSION is required}"

ARCH="$(uname -m)"
case "${ARCH}" in
  x86_64) ARCH="amd64" ;;
  aarch64) ARCH="arm64" ;;
  *)
    echo "unsupported architecture: ${ARCH}" >&2
    exit 1
    ;;
esac

WORKDIR="/tmp/etcd"
rm -rf "${WORKDIR}"
mkdir -p "${WORKDIR}"
cd "${WORKDIR}"

wget -q --show-progress --https-only --timestamping \
  "https://github.com/etcd-io/etcd/releases/download/v${ETCD_VERSION}/etcd-v${ETCD_VERSION}-linux-${ARCH}.tar.gz"

tar -xvf "etcd-v${ETCD_VERSION}-linux-${ARCH}.tar.gz"
sudo install -m 0755 "etcd-v${ETCD_VERSION}-linux-${ARCH}/etcd" "/usr/local/bin/etcd"
sudo install -m 0755 "etcd-v${ETCD_VERSION}-linux-${ARCH}/etcdctl" "/usr/local/bin/etcdctl"

rm -rf "etcd-v${ETCD_VERSION}-linux-${ARCH}"

etcd --version
etcdctl version

cd /
rm -rf "${WORKDIR}"
