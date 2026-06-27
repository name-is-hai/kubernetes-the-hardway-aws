# AWS Self-Managed Kubernetes Hard-Way Lab Plan

This plan keeps the project build incremental. Do not move to the next phase until the validation commands for the current phase pass from a clean setup.

## Project Shape

- Terraform owns AWS infrastructure.
- Packer builds the reusable base AMI after Ansible is proven.
- Ansible installs and configures Kubernetes.
- S3 cache stores manifests, Helm charts, checksums, and optional binaries.
- Scripts provide one-command workflows.
- Tests validate cluster behavior and workload performance.

## Operating Rules

- Build Terraform first. Do not start Kubernetes until networking and EC2 are stable.
- Keep the S3 cache bucket only if preserving cached assets is intentional.
- Do not commit certificates, kubeconfigs, private keys, `.env`, or Terraform state.
- Keep cluster-specific values in Ansible, not in the AMI.
- Destroy the environment after study sessions to control cost.
- Treat a phase as complete only after its validation commands pass.

## Phase 1: Terraform Infrastructure

Goal: create AWS networking and EC2 nodes with no Kubernetes installed.

Build:

- VPC.
- 3 public subnets.
- 3 private subnets.
- 1 NAT Gateway.
- Route tables.
- Security groups.
- IAM role and instance profile for EC2.
- 3 control-plane EC2 instances.
- 3 worker EC2 instances.
- Internal NLB for the Kubernetes API.
- Public ALB for application ingress.
- S3 Gateway Endpoint.
- S3 cache bucket.

Required EC2 tagging:

- `Project = k8s-hardway`
- `Environment = dev`
- `Role = control-plane` or `worker`
- `Name = cp-01`, `cp-02`, `cp-03`, `worker-01`, `worker-02`, or `worker-03`

Required subnet tagging:

- Every subnet should have `Project = k8s-hardway`.
- Every subnet should have `Environment = dev`.
- Every subnet should have a clear `Name`.
- Public subnets should have `Tier = public`.
- Private subnets should have `Tier = private`.

Future AWS Load Balancer Controller subnet discovery tags:

- Public subnets: `kubernetes.io/role/elb = 1`
- Private subnets: `kubernetes.io/role/internal-elb = 1`

These Kubernetes subnet tags are not required for plain EC2 or Terraform. They are useful if the cluster later uses AWS Load Balancer Controller or EKS-style automation to discover which subnets should receive internet-facing or internal load balancers.

Validation:

```bash
terraform -chdir=terraform/environments/dev init
terraform -chdir=terraform/environments/dev apply
terraform -chdir=terraform/environments/dev output
aws ec2 describe-instances --filters "Name=tag:Project,Values=k8s-hardway"
terraform -chdir=terraform/environments/dev destroy
```

Done when:

- Terraform can create and destroy all infrastructure cleanly.
- Outputs include control-plane private IPs, worker private IPs, API NLB DNS, app ALB DNS, and S3 cache bucket name.
- EC2 instances are discoverable by AWS tags.
- No Kubernetes or Ansible configuration is required for this phase to pass.

## Phase 2: Ansible Common Setup

Goal: Ansible can connect to all private nodes and configure Linux basics.

Build:

- Dynamic EC2 inventory.
- Host grouping from `Role` tags.
- Base packages.
- Kernel modules: `overlay`, `br_netfilter`.
- Required sysctl values.
- Swap disabled.
- Containerd installed and running.
- Base Kubernetes directories.

Validation:

```bash
ansible all -i ansible/inventory/aws_ec2.yml -m ping
ansible-playbook -i ansible/inventory/aws_ec2.yml ansible/playbooks/01-common.yml
```

Done when:

- All six nodes respond to Ansible ping by private IP.
- `role_control_plane` and `role_worker` groups are populated.
- Containerd is enabled and running on every node.
- The common playbook is idempotent on a second run.

## Phase 3: Kubernetes Hard-Way Core

Goal: bring up etcd, the Kubernetes control plane, and workers.

Build:

- Cluster CA and etcd CA.
- API server certificate.
- Kubelet certificates.
- Admin, controller-manager, and scheduler certificates.
- Service account keys.
- Kubeconfigs.
- Etcd on the 3 control-plane nodes.
- Kube-apiserver.
- Kube-controller-manager.
- Kube-scheduler.
- Kubelet.
- Kube-proxy.
- Local admin `kubectl` configuration.

Validation:

```bash
kubectl get nodes
kubectl get pods -A
etcdctl endpoint health
```

Done when:

- Etcd is healthy on all control-plane nodes.
- The API server is reachable through the internal NLB.
- All six nodes register with Kubernetes.
- Control-plane components run under systemd.
- Worker services run under systemd.

## Phase 4: Cluster Addons

Goal: make the cluster usable for normal workloads.

Build:

- CNI: Calico or Cilium.
- CoreDNS.
- Ingress controller.
- Metrics Server.

Validation:

```bash
kubectl get nodes
kubectl run test --image=nginx
kubectl expose deployment test --port=80
kubectl top nodes
```

Done when:

- All nodes are `Ready`.
- CoreDNS pods are healthy.
- Pods can resolve Kubernetes service DNS names.
- A basic service is reachable inside the cluster.
- Metrics Server returns node and pod metrics.

## Phase 5: Observability and Load Test

Goal: prove the cluster works under a realistic workload.

Build:

- Prometheus.
- Grafana.
- Loki or Grafana Alloy.
- k6 smoke and load tests.
- Validation scripts.

Validation:

```bash
./scripts/validate-cluster.sh
./scripts/run-load-test.sh
```

Done when:

- Smoke app deploys successfully.
- DNS, service routing, ingress, metrics, and logs checks pass.
- k6 smoke test passes.
- k6 load test results are captured.

## Phase 6: Move Stable Setup Into AMI

Goal: reduce daily build time only after Ansible works from scratch.

Move into the Packer AMI:

- OS packages.
- Containerd.
- runc.
- crictl.
- Kubernetes binaries.
- Etcd binary.
- Kernel modules.
- Sysctl defaults.
- Base directories.
- Generic systemd templates.

Keep in Ansible:

- Certificates.
- Kubeconfigs.
- Private IP configuration.
- Etcd cluster configuration.
- API server SANs.
- Service CIDR.
- Pod CIDR.
- CNI install.
- Ingress install.
- Monitoring and logging install.
- Validation.

Validation:

```bash
make ami
make up
./scripts/validate-cluster.sh
make down
```

Done when:

- AMI build succeeds.
- A fresh cluster can be created from the AMI.
- No secrets, keys, certs, kubeconfigs, or hardcoded node IPs are baked into the AMI.

## Daily Workflow

Bring the lab up:

```bash
make up
```

Expected `make up` flow:

```bash
terraform -chdir=terraform/environments/dev apply -auto-approve
ansible-playbook -i ansible/inventory/aws_ec2.yml ansible/site.yml
./scripts/validate-cluster.sh
```

Run checks:

```bash
kubectl get nodes
kubectl get pods -A
./scripts/run-load-test.sh
```

Destroy the lab:

```bash
make down
```

Expected `make down` flow:

```bash
terraform -chdir=terraform/environments/dev destroy -auto-approve
```

## Milestones

1. `make up`, Ansible ping works, then `make down`.
2. Containerd installed on all nodes, then `make down`.
3. Etcd healthy on 3 control-plane nodes, then `make down`.
4. `kubectl get nodes` shows all 6 nodes `Ready`, then `make down`.
5. Smoke workload, ingress, and metrics pass, then `make down`.
6. Packer AMI builds and a fresh cluster still validates.

## Final Acceptance Criteria

- AWS networking is reproducible with Terraform.
- Six EC2 nodes are discoverable through tags and private IPs.
- Ansible configures Linux, containerd, Kubernetes, and addons idempotently.
- Kubernetes control plane and workers recover from a clean rebuild.
- S3 cache supports cached manifests, Helm charts, checksums, and optional binaries.
- Validation and load test scripts pass.
- Daily workflow is `make up`, test, then `make down`.
