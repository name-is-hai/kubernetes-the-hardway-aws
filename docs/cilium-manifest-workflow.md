# Cilium Manifest Workflow

This project treats Cilium as a rendered, reviewed Kubernetes add-on, not as a live
installer step.

## Policy

1. Use the Cilium CLI or Helm only to render manifests.
2. Commit the rendered YAML to the repo and optionally mirror it into the S3 cache.
3. Apply the rendered YAML with Ansible.
4. Pin the Cilium version.
5. Keep the values and install assumptions documented.

## Why

Rendering first makes the cluster reproducible. A rebuild should apply the same
Cilium objects every time instead of depending on whatever the CLI, Helm repo, or
network returns during the Ansible run.

Rendered manifests also make review possible. CRDs, RBAC, DaemonSets, operator
settings, security contexts, and CNI behavior can be inspected before they touch
the cluster.

## Intended Layout

```text
k8s/cilium/
  values.yaml
  cilium.yaml
  README.md
```

`values.yaml` records the inputs used to render the manifest.

`cilium.yaml` is the rendered manifest applied by Ansible.

`README.md` explains the selected Cilium mode, version, and tradeoffs.

The same rendered manifest can be mirrored to the project S3 cache for air-gapped
or repeatable apply workflows, but the checked-in YAML remains the reviewable
source for the lab.

## Version Pinning

Pin the Cilium version explicitly. Do not render from an unqualified latest chart
or CLI default.

Example with Helm:

```bash
helm template cilium cilium/cilium \
  --namespace kube-system \
  --version 1.19.3 \
  --values k8s/cilium/values.yaml \
  > k8s/cilium/cilium.yaml
```

If the Cilium CLI is used instead of Helm, use its dry-run/render mode only and
record the exact command in `k8s/cilium/README.md`.

Use the exact version selected for the repo. The command above shows the workflow,
not a permanent version decision.

## Ansible Role Boundary

Ansible should copy the committed manifest to a control-plane host and apply it:

```bash
kubectl --kubeconfig /etc/kubernetes/admin.kubeconfig apply -f /tmp/cilium.yaml
```

Ansible should not run `cilium install` or `helm install` directly against the
cluster. That keeps rendering, review, caching, and applying as separate steps.

## Initial Cilium Assumptions

Start with the smallest Cilium change set:

- Overlay or tunnel mode first.
- Keep kube-proxy enabled initially.
- Do not enable kube-proxy replacement in the first pass.
- Do not enable Hubble in the first pass unless it is being tested deliberately.
- Use Cilium for pod networking and NetworkPolicy enforcement.

Advanced networking work can later evaluate native routing, Hubble, and
kube-proxy replacement after the baseline Cilium install is stable.
