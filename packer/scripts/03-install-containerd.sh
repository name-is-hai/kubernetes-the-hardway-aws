#!/usr/bin/env bash
set -euo pipefail

: "${CONTAINERD_VERSION:?CONTAINERD_VERSION is required}"
: "${RUNC_VERSION:?RUNC_VERSION is required}"
: "${CRICTL_VERSION:?CRICTL_VERSION is required}"

mkdir /tmp/containerd
cd /tmp/containerd

ARCH="$(uname -m)"
case "$ARCH" in
  x86_64) ARCH="amd64" ;;
  aarch64) ARCH="arm64" ;;
*)
  echo "unsupported architecture: ${ARCH}" >&2
  exit 1
  ;;
esac

cat << EOF > downloads.txt
https://github.com/kubernetes-sigs/cri-tools/releases/download/v${CRICTL_VERSION}/crictl-v${CRICTL_VERSION}-linux-${ARCH}.tar.gz
https://github.com/opencontainers/runc/releases/download/v${RUNC_VERSION}/runc.${ARCH}
https://github.com/containerd/containerd/releases/download/v${CONTAINERD_VERSION}/containerd-${CONTAINERD_VERSION}-linux-${ARCH}.tar.gz
EOF

wget -q --show-progress \
  --https-only \
  --timestamping \
  -P downloads \
  -i downloads.txt

sudo tar -xvf downloads/crictl-v${CRICTL_VERSION}-linux-${ARCH}.tar.gz \
  -C /usr/local/bin

sudo tar -xvf downloads/containerd-${CONTAINERD_VERSION}-linux-${ARCH}.tar.gz \
  --strip-components 1 \
  -C /usr/local/bin

sudo install -m 755 downloads/runc.${ARCH} /usr/local/sbin/runc

sudo wget -q \
  -O /etc/systemd/system/containerd.service \
  https://raw.githubusercontent.com/containerd/containerd/v${CONTAINERD_VERSION}/containerd.service

sudo mkdir -p /etc/containerd

containerd config default | sudo tee /etc/containerd/config.toml >/dev/null

sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

sudo tee /etc/crictl.yaml >/dev/null <<'EOF'
runtime-endpoint: unix:///run/containerd/containerd.sock
image-endpoint: unix:///run/containerd/containerd.sock
timeout: 10
debug: false
EOF

sudo systemctl daemon-reload
sudo systemctl enable containerd
sudo systemctl start containerd

containerd --version
runc --version
crictl --version
sudo systemctl is-active --quiet containerd

cd /
sudo rm -rf /tmp/containerd
