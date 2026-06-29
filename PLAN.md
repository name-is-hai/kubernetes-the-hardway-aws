# AWS Self-Managed Kubernetes Hard-Way Lab Plan

## Project Shape

- Terraform owns AWS infrastructure.
- Packer builds reusable role-specific AMIs before the cluster nodes are created.
- Ansible installs and configures Kubernetes.
- SSM Session Manager is the default access path for private instances.
- S3 cache stores manifests, Helm charts, checksums, and optional binaries.
- Scripts provide one-command workflows.
- Tests validate cluster behavior and workload performance.

## Phase 0: Terraform Backend Bootstrap

Learn:
- Terraform local state vs remote state.
- S3 backend.
- State locking.
- AWS credentials for backend init.

Build:
- S3 bucket for Terraform state.
- Versioning.
- Encryption.
- Public access block.
- Optional lockfile support.

Validate:

```bash
aws sts get-caller-identity
terraform -chdir=terraform/bootstrap init
terraform -chdir=terraform/bootstrap apply
terraform -chdir=terraform/environments/dev init
```

Done when:
- Remote backend initializes successfully.
- State is stored in S3.
- No state files are committed.

## Phase 1: AWS Network Foundation

Learn:
- VPC is regional.
- Subnets are AZ-level.
- CIDR blocks.
- DNS support and DNS hostnames.
- Internet Gateway.
- Regional NAT Gateway.
- Route tables.
- Public vs private subnets.
- Private instance access with SSM instead of public SSH or bastion hosts.
- VPC endpoints vs NAT Gateway for AWS service access.

Build:
- VPC.
- 3 public subnets.
- 3 private subnets.
- Internet Gateway.
- Regional NAT Gateway.
- Public route table.
- Private route tables.
- S3 Gateway Endpoint.
- Interface VPC Endpoints for SSM:
  - `ssm`
  - `ssmmessages`
  - `ec2messages`
- Endpoint security group allowing HTTPS from private subnets.
- Required tags.

Validate:
```bash
terraform -chdir=terraform/environments/dev apply
terraform -chdir=terraform/environments/dev output
aws ec2 describe-route-tables --filters "Name=tag:Project,Values=k8s-hardway"
aws ec2 describe-vpc-endpoints --filters "Name=tag:Project,Values=k8s-hardway"
```

Inspect:
- Public subnets route `0.0.0.0/0` to IGW.
- Private subnets route `0.0.0.0/0` to NAT.
- S3 endpoint routes are attached to private route tables.
- SSM interface endpoints are attached to private subnets.
- Private instances can reach SSM over HTTPS without inbound SSH.
- Subnets are spread across AZs.

Done when:
- Networking applies and destroys cleanly.
- Route tables match the expected design.
- SSM endpoint plumbing exists for private EC2 access.
- No EC2 or Kubernetes yet.

## Phase 2: Build Kubernetes-Ready Base AMIs

Learn:
- Difference between normal AMI and Kubernetes-ready AMI.
- Difference between a control-plane AMI and a worker AMI.
- What is safe to bake.
- What must stay dynamic.
- Packer workflow.
- Parallel Packer builds.
- Packer connection through SSM Session Manager.
- Why AMI builders should run in private subnets.

Build common base into both AMIs:
- Base packages.
- SSM Agent installed/enabled if the base AMI does not already include it.
- `containerd`.
- `runc`.
- `crictl`.
- `kubelet`.
- `kubectl`.
- CNI plugins.
- Helm.
- Kernel modules config.
- Sysctl defaults.
- Swap disabled config.
- Base directories:
  - `/etc/kubernetes`
  - `/etc/kubernetes/pki`
  - `/var/lib/kubelet`
  - `/opt/cni/bin`

Build control-plane AMI with:
- Common base.
- `kube-apiserver`.
- `kube-controller-manager`.
- `kube-scheduler`.
- `etcd`.
- `etcdctl`.
- `/var/lib/etcd`

Build worker AMI with:
- Common base.
- `kube-proxy`.

Do not bake:
- Certificates.
- Private keys.
- Kubeconfigs.
- AWS credentials.
- Etcd data.
- Node names.
- Private IPs.
- API server SANs.
- Cluster tokens.
- Runtime cluster state.

Packer access model:
- Launch temporary builders in private subnets.
- Do not associate public IPs.
- Use the Packer SSM communicator or SSM-backed SSH tunnel.
- Give each builder an IAM instance profile with SSM permissions.
- Allow outbound HTTPS to SSM endpoints, S3, package repositories, and optional registry endpoints.
- Use NAT Gateway for public package downloads unless all dependencies are mirrored behind VPC endpoints or private registry access.

Parallel build model:
- Build `k8s-control-plane` and `k8s-worker` AMIs from the same base OS AMI.
- Run builds in parallel when possible because they do not depend on each other.
- Keep shared install logic identical where possible to avoid version drift.
- Output separate AMI IDs for Terraform:
  - `control_plane_ami_id`
  - `worker_ami_id`

Validate:
```bash
packer validate packer/k8s-base.pkr.hcl
packer build packer/k8s-base.pkr.hcl
```

Optional smoke EC2 validation:
```bash
containerd --version
crictl --version
kubelet --version
kubectl version --client
```

Done when:
- Both AMIs build successfully.
- No Packer builder receives a public IP.
- Private test EC2 instances launched from both AMIs are reachable through SSM.
- A test EC2 launched from the control-plane AMI has control-plane and etcd binaries.
- A test EC2 launched from the worker AMI has worker/runtime binaries.
- No secrets or cluster identity exist in either AMI.

## Phase 3: Terraform Compute Layer

Learn:
- EC2 instances in private subnets.
- IAM instance profiles.
- Security groups.
- Load balancers.
- EC2 tags for Ansible inventory.

Build:
- IAM role and instance profile.
- Security groups.
- 3 control-plane EC2 instances using the control-plane AMI.
- 3 worker EC2 instances using the worker AMI.
- No public IPs on control-plane or worker instances.
- SSM permissions attached to all node instance profiles.
- Internal NLB for Kubernetes API.
- Public ALB or NLB for ingress path later.

Tags:
- `Project = k8s-hardway`
- `Environment = dev`
- `Role = control-plane` or `worker`
- `Name = cp-01`, `cp-02`, `cp-03`, `worker-01`, `worker-02`, `worker-03`

Validate:
```bash
terraform -chdir=terraform/environments/dev apply
terraform -chdir=terraform/environments/dev output
aws ec2 describe-instances --filters "Name=tag:Project,Values=k8s-hardway"
```

Done when:
- All six instances launch from the correct role-specific AMI.
- Instances are private.
- Nodes are reachable through SSM Session Manager.
- Tags are correct.
- Load balancer target groups attach to the right nodes.

## Phase 4: Ansible Connectivity and Final Host Setup

Learn:
- Dynamic inventory.
- Private IP access.
- Host groups from EC2 tags.
- Ansible over AWS SSM Session Manager.
- Idempotent configuration.

Access model:
- Ansible connects to private EC2 instances through SSM, not public SSH.
- No bastion host is required.
- No inbound SSH rule is required on Kubernetes nodes.
- Inventory still comes from EC2 tags.

Ansible should verify/configure:
- Hostname.
- Required directories.
- Kernel modules loaded.
- Sysctl values.
- Swap disabled.
- Containerd enabled/running.
- Binaries present.
- Time sync.
- Basic node prerequisites.

Validate:
```bash
aws ssm describe-instance-information
ansible all -i ansible/inventory/aws_ec2.yml -m ping
ansible-playbook -i ansible/inventory/aws_ec2.yml ansible/playbooks/01-common.yml
```

Done when:
- All six nodes respond.
- Ansible reaches nodes through SSM.
- `role_control_plane` and `role_worker` groups are correct.
- Common playbook is mostly verification/rendering, not slow installation.
- Second Ansible run is idempotent.

## Phase 5: Certificates and Kubeconfigs

Learn:
- Kubernetes PKI.
- Client certs vs server certs.
- API server SANs.
- Kubeconfigs.

Build:
- Cluster CA.
- Etcd CA.
- API server cert.
- Etcd certs.
- Kubelet certs.
- Admin cert.
- Controller-manager cert.
- Scheduler cert.
- Service account keys.
- Kubeconfigs.

Keep generated files outside git.

Validate:
```bash
openssl x509 -in ansible/generated/pki/ca.crt -noout -subject
```

Done when:
- Certs are generated once per cluster build.
- Correct certs are copied to correct nodes.
- Private keys are not committed.

## Phase 6: Etcd Cluster

Learn:
- Etcd quorum.
- Peer URLs.
- Client URLs.
- Initial cluster string.
- Systemd services.

Ansible configures:
- `etcd.service`.
- Member name per control-plane node.
- Peer/client cert paths.
- Initial cluster using private IPs.
- Etcd data directory.

Validate:
```bash
etcdctl endpoint health
etcdctl member list
```

Done when:
- 3-member etcd cluster is healthy.
- Each control-plane node has unique etcd identity.
- Etcd survives service restart.

## Phase 7: Kubernetes Control Plane

Learn:
- API server.
- Controller manager.
- Scheduler.
- Service account signing.
- Encryption config.
- Audit policy.

Ansible configures:
- `kube-apiserver.service`.
- `kube-controller-manager.service`.
- `kube-scheduler.service`.
- Admin kubeconfig.
- Controller/scheduler kubeconfigs.
- API NLB endpoint in kubeconfigs.

Validate:
```bash
kubectl cluster-info
kubectl get componentstatuses || true
kubectl get --raw=/readyz
```

Done when:
- API server is reachable through the internal NLB.
- Controller manager and scheduler are running.
- `kubectl` can authenticate as admin.

## Phase 8: Worker Nodes

Learn:
- Kubelet.
- Kube-proxy.
- Node registration.
- CRI connection to containerd.
- Node identity.

Ansible configures:
- `kubelet.service`.
- `kubelet-config.yaml`.
- `kube-proxy.service`.
- `kube-proxy-config.yaml`.
- Per-node kubeconfig.
- Node labels if needed.

Validate:
```bash
kubectl get nodes
journalctl -u kubelet --no-pager
```

Done when:
- All 6 nodes register.
- Nodes may be `NotReady` until CNI is installed.
- Kubelet uses containerd correctly.

## Phase 9: CNI and CoreDNS

Learn:
- Pod networking.
- Service networking.
- DNS inside Kubernetes.

Install:
- Calico or Cilium.
- CoreDNS.

Validate:
```bash
kubectl get nodes
kubectl get pods -A
kubectl run dns-test --image=busybox:1.36 --restart=Never -- nslookup kubernetes.default
```

Done when:
- Nodes are `Ready`.
- Pods can start.
- DNS works.

## Phase 10: Ingress and App Traffic

Learn:
- Service vs ingress.
- Ingress controller.
- ALB/NLB path.
- Host headers.

Install:
- Ingress controller.
- Smoke app.
- App service.
- Ingress object.

Validate:
```bash
kubectl apply -f k8s/smoke-app/
kubectl rollout status deployment/smoke-api -n smoke
curl -H "Host: smoke.example.local" http://<alb-dns-name>
```

Done when:
- Smoke app responds through ingress.
- Public traffic reaches worker nodes through the intended load balancer path.

## Phase 11: Metrics, Logging, and Load Test

Learn:
- Metrics Server.
- Prometheus.
- Grafana.
- Loki or Alloy.
- k6 load testing.

Install:
- Metrics Server.
- kube-prometheus-stack.
- Loki or Grafana Alloy.
- k6 scripts.

Validate:
```bash
kubectl top nodes
kubectl top pods -A
./scripts/validate-cluster.sh
./scripts/run-load-test.sh
```

Done when:
- Metrics are visible.
- Logs are collected.
- Smoke and load tests pass.

## Daily Workflow After AMI Exists

```bash
make up
kubectl get nodes
kubectl get pods -A
./scripts/run-load-test.sh
make down
```

Expected `make up`:

```bash
terraform -chdir=terraform/environments/dev apply -auto-approve
ansible-playbook -i ansible/inventory/aws_ec2.yml ansible/site.yml
./scripts/validate-cluster.sh
```

## AMI Rebuild Rule

Rebuild both AMIs when these shared inputs change:

- OS package list.
- Containerd version.
- Kubernetes version.
- CNI plugin binaries.
- Base sysctl/kernel settings.
- Base directory layout.

Rebuild only the control-plane AMI when these change:

- Etcd version.
- Control-plane binary install layout.

Rebuild only the worker AMI when these change:

- Worker-only binary install layout.
- Worker-only runtime prerequisites.

Do not rebuild either AMI for:

- Certificates.
- Kubeconfigs.
- Node IPs.
- Etcd cluster membership.
- API server SANs.
- CNI manifests.
- Monitoring manifests.
- App manifests.

## Final Acceptance Criteria

- Terraform can create and destroy AWS infrastructure repeatedly.
- EC2 nodes launch from the correct role-specific Kubernetes-ready AMI.
- Ansible only applies cluster-specific setup.
- Etcd is healthy.
- Kubernetes nodes become Ready.
- Smoke app works.
- Metrics/logging/load tests pass.
- No secrets or cluster identity are baked into either AMI.
