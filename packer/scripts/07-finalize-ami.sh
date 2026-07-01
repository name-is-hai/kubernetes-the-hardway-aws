#!/usr/bin/env bash
set -euo pipefail

ROLE="${1:?usage: 07-finalize-ami.sh <control-plane|worker>}"

case "${ROLE}" in
  control-plane|worker) ;;
  *)
    echo "unknown role: ${ROLE}" >&2
    exit 1
    ;;
esac

if [ -d /etc/kubernetes/pki ]; then
  sudo find /etc/kubernetes/pki -mindepth 1 -delete
fi

if [ -d /etc/kubernetes ]; then
  sudo rm -f /etc/kubernetes/*.conf
  sudo rm -f /etc/kubernetes/*.kubeconfig
fi

if [ -d /var/lib/kubelet ]; then
  sudo rm -f /var/lib/kubelet/kubeconfig
fi

if [ "${ROLE}" = "control-plane" ] && [ -d /var/lib/etcd ]; then
  sudo find /var/lib/etcd -mindepth 1 -delete
fi

sudo dnf clean all || true
sudo rm -rf /var/cache/dnf /tmp/* /var/tmp/*

sudo journalctl --rotate || true
sudo journalctl --vacuum-time=1s || true
