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
- VPC CIDR: `192.168.0.0/16`.
- 3 public subnets:
  - `192.168.1.0/24`
  - `192.168.2.0/24`
  - `192.168.3.0/24`
- 3 private subnets:
  - `192.168.10.0/24`
  - `192.168.20.0/24`
  - `192.168.30.0/24`
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
- CNI plugin binaries for fallback/debug use.
- Helm.
- `/opt/cni/bin` populated with standard CNI plugin binaries where useful.
- Cilium is not baked into the AMI; render and apply it in Phase 9 so its
  manifest, CRDs, and runtime settings remain cluster-specific.

Build control-plane AMI with:
- Common base.
- `kube-apiserver`.
- `kube-controller-manager`.
- `kube-scheduler`.
- `etcd`.
- `etcdctl`.

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
- Give each builder the Packer builder IAM instance profile with SSM permissions.
- Allow outbound HTTPS to SSM endpoints, S3, package repositories, and optional registry endpoints.
- Use NAT Gateway for public package downloads unless all dependencies are mirrored behind VPC endpoints or private registry access.

Learning boundary:
- Packer bakes reusable software only.
- Packer does not configure Kubernetes host prerequisites such as kernel modules, sysctl values, swap state, or live-node state directories.
- Live-node setup in Phase 4 explains and applies those prerequisites so the lab stays close to Kubernetes the Hard Way.

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
- IAM roles and instance profiles:
  - Packer builder role/profile.
  - Control-plane node role/profile.
  - Worker node role/profile.
- Security groups.
- 3 control-plane EC2 instances using the control-plane AMI.
- 3 worker EC2 instances using the worker AMI.
- No public IPs on control-plane or worker instances.
- SSM permissions attached to all node instance profiles.
- Internal NLB for Kubernetes API.
- Public ALB or NLB for ingress path later.

IAM model:
- Packer builder role is used only by temporary Packer AMI builder instances.
- Control-plane node role is used by control-plane EC2 instances.
- Worker node role is used by worker EC2 instances.
- All three roles initially attach `AmazonSSMManagedInstanceCore`.
- Add S3, ECR, CloudWatch, KMS, or private registry permissions later only to the role that needs them.

Security group egress model:
- Do not use default egress-all for control-plane or worker nodes.
- Allow only explicit outbound paths needed by private nodes.
- Allow TCP `443` to VPC endpoint destinations for SSM and AWS service endpoints.
- Allow DNS to the VPC resolver, for example `192.168.0.2` in the `192.168.0.0/16` VPC.
- Allow Kubernetes internal traffic inside the VPC, such as API server `6443`, etcd `2379-2380`, and kubelet `10250`.
- Add TCP `443` to `0.0.0.0/0` only if nodes must reach public internet dependencies through NAT.

Load balancer security group model:
- An internal API NLB fronts `kube-apiserver` on TCP `6443`.
- DNS resolution for the NLB name is handled by node egress to the VPC resolver; the NLB does not need DNS egress.
- If the API NLB is created without a security group, worker egress to TCP `6443` must allow the NLB private IPs, usually by allowing the VPC CIDR or the private subnet CIDRs where the NLB is placed.
- If using NLB security group support, attach a dedicated NLB security group and allow:
  - Worker/control-plane clients to egress TCP `6443` to the NLB security group.
  - The NLB security group to reach control-plane targets on TCP `6443`.
  - Control-plane targets to allow TCP `6443` from the NLB security group.
- Do not confuse worker-to-API traffic with API-server-to-kubelet traffic. `kubectl logs`, `exec`, `attach`, and `port-forward` require control-plane egress to worker kubelet TCP `10250` and worker ingress from the control-plane security group on TCP `10250`.

Tags:
- `Project = k8s-hardway`
- `Environment = dev`
- `Role = control-plane` or `worker`
- `Name = cp-01`, `cp-02`, `cp-03`, `worker-01`, `worker-02`, `worker-03`

Validate:
```bash
terraform -chdir=terraform/environments/dev fmt -check -recursive
terraform -chdir=terraform/environments/dev init
terraform -chdir=terraform/environments/dev validate
terraform -chdir=terraform/environments/dev plan
terraform -chdir=terraform/environments/dev apply
terraform -chdir=terraform/environments/dev output
```

Verify EC2 instances:
```bash
aws ec2 describe-instances --filters "Name=tag:Project,Values=k8s-hardway"

aws ec2 describe-instances \
  --filters "Name=tag:Project,Values=k8s-hardway" \
  --query 'Reservations[].Instances[].{Name:Tags[?Key==`Name`]|[0].Value,Role:Tags[?Key==`Role`]|[0].Value,PrivateIp:PrivateIpAddress,PublicIp:PublicIpAddress,State:State.Name,Profile:IamInstanceProfile.Arn,ImageId:ImageId}' \
  --output table
```

Verify SSM:
```bash
aws ssm describe-instance-information \
  --query 'InstanceInformationList[].{InstanceId:InstanceId,PingStatus:PingStatus,Platform:PlatformName,Agent:AgentVersion}' \
  --output table
```

Verify internal API NLB:
```bash
aws elbv2 describe-load-balancers \
  --names internal-cp-nlb \
  --query 'LoadBalancers[].{DNS:DNSName,Scheme:Scheme,Type:Type,State:State.Code,VpcId:VpcId}' \
  --output table

aws elbv2 describe-target-health \
  --target-group-arn <api-target-group-arn> \
  --output table
```

Before `kube-apiserver` is installed, NLB targets may be unhealthy. For Phase 3, verify that the three control-plane instances are registered on port `6443`.

Verify no public SSH path:
```bash
aws ec2 describe-security-groups \
  --filters "Name=tag:Project,Values=k8s-hardway" \
  --query 'SecurityGroups[].{Name:GroupName,Ingress:IpPermissions}' \
  --output json
```

Done when:
- All six instances launch from the correct role-specific AMI.
- Instances are private.
- Nodes are reachable through SSM Session Manager.
- Control-plane nodes use the control-plane instance profile.
- Worker nodes use the worker instance profile.
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
- Required directories:
  - `/etc/kubernetes`
  - `/etc/kubernetes/pki`
  - `/var/lib/kubelet`
  - `/var/lib/etcd` on control-plane nodes
- Kernel modules loaded:
  - `overlay`
  - `br_netfilter`
- Sysctl values:
  - `net.bridge.bridge-nf-call-iptables = 1`
  - `net.bridge.bridge-nf-call-ip6tables = 1`
  - `net.ipv4.ip_forward = 1`
- Swap disabled.
- Containerd enabled/running.
- Binaries present.
- Time sync.
- Basic node prerequisites, with notes explaining why each is required.

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

Cluster network values:
- Kubernetes Service CIDR: `172.16.0.0/24`.
- Kubernetes default service IP: `172.16.0.1`.
- CoreDNS service IP: `172.16.0.10`.
- Kubernetes Pod CIDR: `10.0.0.0/16`.
- These ranges must not overlap the AWS VPC CIDR `192.168.0.0/16`.

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
- Why bridge CNI needs AWS pod routes for cross-node traffic.
- How Cilium provides pod networking without per-node AWS route-table entries.
- Cilium operator, agent DaemonSet, CNI install path, and CRDs.
- Basic NetworkPolicy enforcement with Cilium.
- Why Cilium manifests are rendered and reviewed before Ansible applies them.

Install:
- Cilium in overlay/tunnel mode first.
- Render Cilium YAML with the Cilium CLI or Helm before the Ansible run.
- Commit rendered Cilium YAML under `k8s/cilium/` and optionally mirror it to the S3 cache.
- Apply rendered Cilium YAML with Ansible; do not run `cilium install` or `helm install` live from Ansible.
- Pin the Cilium version and document the values used to render the manifest.
- CoreDNS.

Validate:
```bash
kubectl get nodes
kubectl get pods -A
kubectl -n kube-system get pods -l k8s-app=cilium
kubectl -n kube-system get pods -l name=cilium-operator
kubectl run dns-test --image=busybox:1.36 --restart=Never -- nslookup kubernetes.default
```

Done when:
- Nodes are `Ready`.
- Cilium agent pods are running on every worker.
- Cilium operator is running.
- Rendered Cilium manifests and values are committed and version-pinned.
- Pods can start.
- Pods on different workers can reach each other.
- Services work across workers without manually adding AWS routes for PodCIDRs.
- DNS works.

Advanced follow-up:
- Enable Hubble for flow visibility.
- Add NetworkPolicy examples and verify allowed/denied traffic.
- Evaluate Cilium kube-proxy replacement after the baseline is stable.

## Phase 10: Ingress and App Traffic

Learn:
- Service vs ingress.
- HAProxy Kubernetes Ingress Controller.
- AWS NLB to worker `NodePort` path.
- Layer 4 vs Layer 7 responsibilities.
- Host headers.
- Why `ClusterIP` is internal-only and `NodePort` is the stable AWS target.

Install:
- HAProxy ingress controller rendered from a pinned Helm chart.
- HAProxy `NodePort` service with fixed ports:
  - HTTP: `30080`
  - HTTPS: `30443`
- Public application NLB.
- NLB target groups that point to worker instances on `30080` and `30443`.
- Smoke app.
- App `ClusterIP` service.
- Ingress object.

Validate:
```bash
helm repo add haproxytech https://haproxytech.github.io/helm-charts
helm repo update
helm search repo haproxytech/kubernetes-ingress --versions | head

helm template haproxy-ingress haproxytech/kubernetes-ingress \
  --namespace haproxy-ingress \
  --version <PINNED_CHART_VERSION> \
  -f k8s/haproxy-ingress/values.yaml \
  > k8s/haproxy-ingress/haproxy-ingress.yaml

kubectl --kubeconfig /etc/kubernetes/admin.kubeconfig \
  apply -f k8s/haproxy-ingress/haproxy-ingress.yaml

kubectl --kubeconfig /etc/kubernetes/admin.kubeconfig \
  -n haproxy-ingress get pods,svc -o wide

kubectl --kubeconfig /etc/kubernetes/admin.kubeconfig \
  apply -f k8s/smoke-app/

kubectl --kubeconfig /etc/kubernetes/admin.kubeconfig \
  -n smoke-app rollout status deployment/smoke-app

curl -H "Host: smoke.local" http://<app-nlb-dns-name>
```

Done when:
- HAProxy controller pods are running.
- HAProxy service exposes the expected fixed NodePorts.
- Public traffic reaches worker nodes through the NLB target groups.
- Smoke app responds through HAProxy ingress.
- Host-based routing works.

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

## Advanced Platform Roadmap

Use this after the hard-way baseline is working. The baseline proves the control plane, workers, Cilium CNI, kube-proxy, Services, and DNS. These phases turn the lab into a more production-shaped platform.

### Advanced Networking

Learn:
- How pod traffic crosses nodes.
- Difference between routed pod networking and overlay pod networking.
- Cilium eBPF networking and policy model.
- Cilium overlay vs native routing.
- Hubble flow visibility.
- Cilium NetworkPolicy and Kubernetes NetworkPolicy.
- Service load balancing beyond kube-proxy.

Build:
- Cilium health and connectivity checks.
- Hubble relay and UI or CLI flow inspection.
- NetworkPolicy examples.
- Cross-node pod-to-pod smoke tests.
- DNS and Service tests across nodes.

Done when:
- Pods on different workers can reach each other.
- Service traffic works across workers.
- NetworkPolicy behavior is understood and tested.
- Hubble can show DNS and pod-to-pod flows.

### Ingress And External Traffic

Learn:
- Service types: `ClusterIP`, `NodePort`, `LoadBalancer`.
- Ingress vs Gateway API.
- How AWS ALB/NLB reaches private worker nodes.
- TLS termination options.

Build:
- HAProxy Kubernetes Ingress Controller with a fixed `NodePort` service.
- Public AWS NLB that forwards `80` to worker `30080` and `443` to worker `30443`.
- Smoke app Deployment, Service, and Ingress.
- Optional AWS Load Balancer Controller later.

Done when:
- External traffic reaches a workload through the intended load balancer path.
- Host-based or path-based routing works.

### Storage

Learn:
- PersistentVolume, PersistentVolumeClaim, StorageClass.
- CSI driver responsibilities.
- StatefulSet storage behavior.

Build:
- AWS EBS CSI driver.
- Default or named StorageClass.
- PVC smoke test.
- StatefulSet smoke test.

Done when:
- Pods can dynamically provision EBS-backed volumes.
- Data survives pod rescheduling on the same volume.

### Security

Learn:
- RBAC least privilege.
- Pod Security Admission.
- Kubelet certificate behavior.
- Secrets encryption rotation.
- Audit logging.
- OIDC authentication.

Build:
- Pod Security Admission labels for namespaces.
- Restricted RBAC examples.
- Audit policy tuning.
- Secrets encryption rotation procedure.
- Optional OIDC auth flow.

Done when:
- Admin access is not the only working access path.
- Audit events are useful.
- Workloads run with restricted security defaults where possible.

### Observability

Learn:
- Metrics Server vs Prometheus.
- Node, pod, control-plane, and application metrics.
- Log collection model.
- Alerting basics.

Build:
- Metrics Server.
- Prometheus and Grafana.
- Loki or another log pipeline.
- Alertmanager basics.
- Dashboards for nodes, API server, etcd, CoreDNS, and workloads.

Done when:
- `kubectl top` works.
- Cluster metrics are visible in Grafana.
- Logs from system pods and workloads are queryable.

### Reliability And Operations

Learn:
- Etcd backup and restore.
- Node drain and upgrade flow.
- PodDisruptionBudget.
- Resource requests and limits.
- PriorityClass.
- Quotas and LimitRanges.

Build:
- Etcd snapshot and restore runbook.
- Worker drain test.
- Control-plane rolling restart notes.
- PDB examples.
- Quota and LimitRange examples.
- Automated smoke tests.

Done when:
- The cluster can be validated after rebuilds.
- Etcd recovery is documented and tested.
- Planned node maintenance does not surprise workloads.

### AWS Integration

Learn:
- IAM permissions by component.
- AWS-native load balancing.
- Route53 automation.
- Private registry access.
- Autoscaling boundaries for self-managed clusters.

Build:
- AWS Load Balancer Controller.
- ExternalDNS with Route53.
- EBS CSI IAM permissions.
- Optional image registry/cache path.
- Optional Cluster Autoscaler.

Done when:
- AWS integrations are scoped by least privilege.
- Workloads can expose services and use storage without manual AWS console steps.

Recommended order:
1. Finish CoreDNS and DNS smoke tests.
2. Install Cilium and verify cross-node pod and Service traffic.
3. Add ingress and a smoke app.
4. Add Metrics Server.
5. Add EBS CSI.
6. Add Prometheus, Grafana, and logs.
7. Add security hardening and operational runbooks.

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
