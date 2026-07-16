#!/usr/bin/env bash
set -euo pipefail

INVENTORY="${INVENTORY:-ansible/inventory/aws_ec2.yml}"
CONTROL_PLANE_GROUP="${CONTROL_PLANE_GROUP:-role_control_plane}"

ETCDCTL_CACERT="${ETCDCTL_CACERT:-/etc/etcd/etcd-ca.crt}"
ETCDCTL_CERT="${ETCDCTL_CERT:-/etc/kubernetes/pki/apiserver-etcd-client.crt}"
ETCDCTL_KEY="${ETCDCTL_KEY:-/etc/kubernetes/pki/apiserver-etcd-client.key}"
ETCD_ENDPOINTS="${ETCD_ENDPOINTS:-https://127.0.0.1:2379}"

ansible -i "${INVENTORY}" "${CONTROL_PLANE_GROUP}" -b -m shell -a "
  set -eu

  echo \"=== \$(hostname) ===\"

  etcdctl \
    --cacert='${ETCDCTL_CACERT}' \
    --cert='${ETCDCTL_CERT}' \
    --key='${ETCDCTL_KEY}' \
    --endpoints='${ETCD_ENDPOINTS}' \
    endpoint health
"
