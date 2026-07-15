# Cilium

This directory stores the reviewed Cilium inputs and rendered manifest used by
Phase 9.

## Pinned Version

```text
Cilium chart: 1.19.3
```

The version is pinned in the render command. Do not render from `latest`.

## Initial Mode

- Overlay/tunnel mode with VXLAN.
- Kubernetes IPAM using node PodCIDRs.
- kube-proxy remains enabled.
- kube-proxy replacement is disabled for the first pass.
- Hubble is disabled for the first pass.

This keeps the first Cilium migration focused on pod networking and
NetworkPolicy enforcement. Hubble and kube-proxy replacement are later advanced
networking phases.

## Render

Render the manifest before running Ansible:

```bash
scripts/render-cilium.sh
```

Equivalent Helm command:

```bash
helm repo add cilium https://helm.cilium.io
helm repo update
helm template cilium cilium/cilium \
  --namespace kube-system \
  --version 1.19.3 \
  --values k8s/cilium/values.yaml \
  > k8s/cilium/cilium.yaml
```

Commit `values.yaml`, `cilium.yaml`, and this README together.

## Apply

Ansible applies the rendered manifest:

```bash
ANSIBLE_CONFIG=ansible/ansible.cfg ansible-playbook -i ansible/inventory/aws_ec2.yml ansible/playbooks/06-cni.yml
```

Do not use `helm install`, `helm upgrade`, or `cilium install` directly against
the cluster for this lab flow.
