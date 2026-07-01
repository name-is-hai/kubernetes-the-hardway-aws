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

Private instances use NAT Gateway for public package downloads unless the
dependency is available through a VPC endpoint, private registry, or S3 cache.

Required SSM interface endpoints:

- `ssm`
- `ssmmessages`
- `ec2messages`

The endpoint security group allows HTTPS from the private subnet CIDR ranges.
Kubernetes node security groups do not need inbound SSH for normal operation.

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
