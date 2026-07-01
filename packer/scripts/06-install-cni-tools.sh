#!/usr/bin/env bash
set -euo pipefail

: "${CNI_PLUGINS_VERSION:?CNI_PLUGINS_VERSION is required}"

ARCH=$(uname -m)
case "${ARCH}" in
    x86_64) ARCH=amd64 ;;
    aarch64) ARCH=arm64 ;;
    *) echo "Unsupported architecture: ${ARCH}" >&2
        exit 1
        ;;
esac

WORK_DIR="/tmp/cni-plugins"

rm -rf "${WORK_DIR}"
mkdir -p "${WORK_DIR}"
cd "${WORK_DIR}"

sudo mkdir -p /opt/cni/bin

wget -q --show-progress --https-only --timestamping \
    "https://github.com/containernetworking/plugins/releases/download/v${CNI_PLUGINS_VERSION}/cni-plugins-linux-${ARCH}-v${CNI_PLUGINS_VERSION}.tgz"

sudo tar -xzf "cni-plugins-linux-${ARCH}-v${CNI_PLUGINS_VERSION}.tgz" -C /opt/cni/bin

sudo chmod +x /opt/cni/bin/*

test -x /opt/cni/bin/loopback
test -x /opt/cni/bin/bridge
test -x /opt/cni/bin/host-local

cd /
rm -rf "${WORK_DIR}"
