# Architecture

## Access Model

This lab uses private EC2 instances by default. Packer builders, control-plane
nodes, and worker nodes run in private subnets with no public IP addresses.

SSM Session Manager is the default operator access path:

```text
operator laptop
  -> AWS API / SSM Session Manager
  -> private EC2 instance
```

This avoids public SSH and avoids a bastion host. Instance access is controlled
with IAM, SSM, and security group egress instead of inbound SSH rules.

## IAM Model

The lab uses separate EC2 roles and instance profiles for image building and
node runtime:

- Packer builder role/profile.
- Control-plane node role/profile.
- Worker node role/profile.

All three roles initially attach `AmazonSSMManagedInstanceCore` so private
instances can register with SSM. Additional permissions should be added only to
the role that needs them. For example, Packer may need S3 cache or private
artifact read permissions, while worker nodes may later need ECR pull or
CloudWatch log permissions.

## Network Shape

```text
VPC
  public subnets
    - Internet Gateway
    - NAT Gateway

  private subnets
    - Packer temporary AMI builders
    - Kubernetes control-plane nodes
    - Kubernetes worker nodes
    - SSM interface endpoints
    - S3 gateway endpoint
```

## CIDR Model

This lab keeps AWS networking and Kubernetes virtual networking in separate
private RFC1918 ranges:

```text
AWS VPC:             192.168.0.0/16
Kubernetes Services: 172.16.0.0/24
Kubernetes Pods:     10.0.0.0/16
```

Example AWS subnets:

```text
public subnets:   192.168.1.0/24, 192.168.2.0/24, 192.168.3.0/24
private subnets:  192.168.10.0/24, 192.168.20.0/24, 192.168.30.0/24
```

Example Kubernetes virtual IPs:

```text
kubernetes.default service: 172.16.0.1
CoreDNS service:            172.16.0.10
Pods:                       10.0.0.0/16
```

These ranges must not overlap. AWS owns the VPC range. Kubernetes owns the
Service and Pod ranges through kube-apiserver, kube-proxy, and Cilium.

## Cilium Networking Model

Phase 9 uses Cilium instead of the simple bridge CNI. The bridge CNI was useful
for learning the raw mechanics, but it requires AWS routes for every worker
PodCIDR before pods on different nodes can reliably talk to each other. Cilium is
now the default CNI for this lab so cross-node pod traffic is handled by the CNI
layer instead of by manual VPC route-table entries.

Initial Cilium target:

- Do not bake Cilium into the AMI.
- Render Cilium manifests with the Cilium CLI or Helm before the Ansible run.
- Commit the rendered YAML and keep a cache copy for repeatable installs.
- Apply the rendered YAML with Ansible.
- Pin the Cilium version and document the values used to render it.
- Use overlay/tunnel mode first to avoid per-node AWS PodCIDR routes.
- Keep kube-proxy enabled for the first Cilium pass to reduce the number of
  moving parts.
- Add Hubble and kube-proxy replacement later as advanced networking work.

Cilium owns:

- Pod networking.
- CNI config installation on workers.
- Cross-node pod traffic.
- NetworkPolicy enforcement.
- Cilium CRDs and operator-managed cluster networking state.

kube-proxy still owns Service programming in the initial design. A later phase
can evaluate Cilium kube-proxy replacement once Cilium itself is stable.

Private instances use NAT Gateway for public package downloads unless the
dependency is available through a VPC endpoint, private registry, or S3 cache.

Required SSM interface endpoints:

- `ssm`
- `ssmmessages`
- `ec2messages`

The endpoint security group allows HTTPS from the private subnet CIDR ranges.
Kubernetes node security groups do not need inbound SSH for normal operation.

Cluster node security groups use tight egress. Control-plane and worker nodes
should not keep default outbound-all rules. Start with explicit outbound rules:

- TCP `443` to VPC endpoint destinations for SSM and AWS service endpoints.
- TCP and UDP `53` to the VPC resolver, such as `192.168.0.2` for the
  `192.168.0.0/16` VPC.
- Kubernetes internal ports inside the VPC, including API server `6443`, etcd
  `2379-2380`, and kubelet `10250`.

If a node must reach public repositories or registries through NAT, add TCP
`443` to `0.0.0.0/0` deliberately and remove it once dependencies are mirrored
behind VPC endpoints, S3 cache, ECR, or a private registry.

## Packer Flow

```text
base AMI
  -> temporary private control-plane builder
  -> Packer connects through SSM
  -> install control-plane binaries and reusable runtime tools
  -> create Kubernetes-ready control-plane AMI
  -> terminate temporary control-plane builder

base AMI
  -> temporary private worker builder
  -> Packer connects through SSM
  -> install worker binaries and reusable runtime tools
  -> create Kubernetes-ready worker AMI
  -> terminate temporary worker builder
```

The two Packer builds can run in parallel because neither image depends on the
other. Both AMIs should share common runtime versions where the components
overlap.

The control-plane AMI may contain `kube-apiserver`,
`kube-controller-manager`, `kube-scheduler`, `etcd`, `etcdctl`, `kubelet`,
`containerd`, CNI plugin binaries, Helm, and shared runtime tools.

The worker AMI may contain `kubelet`, `kube-proxy`, `containerd`, CNI plugins,
Helm, and shared runtime tools.

Kernel modules, sysctl values, swap state, and Kubernetes live-node state
directories are configured later during live-node setup. Keeping those steps
out of Packer makes the lab closer to Kubernetes the Hard Way because the
operator sees why each running node needs those settings.

Neither AMI may contain certificates, private keys, kubeconfigs, AWS
credentials, node names, private IPs, cluster tokens, etcd data, or any runtime
cluster identity.

## Ansible Flow

```text
EC2 tags
  -> dynamic inventory
  -> Ansible connects through SSM
  -> configure cluster-specific state on private nodes
```

Ansible handles dynamic cluster identity such as certificates, kubeconfigs,
systemd unit rendering, node-specific IPs, etcd membership, and Kubernetes
control-plane or worker configuration.
