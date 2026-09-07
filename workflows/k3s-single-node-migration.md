# Workflow: Migrate from 3-Node k3s to Single-Node k3s

## Problem Statement

The 3-node k3s simulation (1 control-plane + 2 workers in isolated network namespaces) consumes
~1.5 GB of pure Kubernetes orchestration overhead (3x kubelet, 3x flannel, 3x CoreDNS) on top of
the platform workloads. Combined with browser/Electron apps on the Windows host consuming >2 GB,
k9s reports ~80% RAM usage on the 16 GB machine and new pods OOMKill on startup.

**Root cause**: The 3-node netns simulation was designed for architectural realism, not EKS
compatibility. It is not how EKS works (EKS manages separate EC2 VMs; it does not use Linux
network namespaces). The node labels, nodeSelectors, and Kubernetes manifests are fully portable --
the multi-process simulation is not.

## Target State

| Dimension | Before | After |
|---|---|---|
| k3s processes | 3 (server + 2 agents in netns) | 1 (server only, untainted) |
| K8s overhead | ~1.5 GB (3x kubelet+flannel+DNS) | ~500 MB (1x kubelet+flannel+DNS) |
| Network arch | Isolated netns bridge k3s-br0 | Direct WSL2 loopback |
| Storage | Longhorn CSI (longhorn-isolated) | local-path (local-path) |
| Dropped services | -- | Loki, Promtail, Jaeger (deferred) |
| Kept services | All core | Kong, Redpanda, Flink, MinIO, Spark, Argo Workflows, ArgoCD, Prometheus, Grafana, Vault |
| kubectl context | k3s-data-platform | k3s-data-platform (unchanged) |
| EKS compatibility | No - netns simulation | Yes - same manifests work on EKS |

**Estimated memory freed**: ~1.8 GB (1.5 GB Kubernetes overhead + 288 MB Loki/Jaeger)

## Trigger

Manual. Run this workflow whenever the k3s cluster needs to be re-provisioned on a memory-
constrained machine. Also run on fresh WSL2 distro setup.

## Checkpoints

One checkpoint after Phase 2 (cluster up, nodes verified) before deploying workloads. This lets
the operator verify the single-node cluster is healthy before re-applying all platform manifests.

---

## Phase 0: Pre-flight

> Estimate 5 minutes. All commands run inside WSL2 (AlmaLinux-10).

```bash
# Record current RAM baseline before teardown (for comparison after)
free -h

# Verify k9s / kubectl memory reading
kubectl top nodes 2>/dev/null || echo "metrics-server not yet available"

# Confirm teardown was already run (from prior session)
pgrep -a k3s || echo "No k3s processes detected -- teardown confirmed"
```

---

## Phase 1: Nuclear Wipe

> Estimate 3 minutes. Destroys all k3s state, netns bridges, and Longhorn artifacts.

```bash
# 1a. Stop and disable all k3s systemd units
sudo systemctl stop k3s k3s-worker-stream k3s-worker-batch 2>/dev/null || true
sudo systemctl disable k3s k3s-worker-stream k3s-worker-batch 2>/dev/null || true
sudo rm -f /etc/systemd/system/k3s-worker-stream.service
sudo rm -f /etc/systemd/system/k3s-worker-batch.service
sudo systemctl daemon-reload

# 1b. Uninstall k3s binary and its data
if command -v k3s-uninstall.sh &>/dev/null; then
    sudo k3s-uninstall.sh
fi

# 1c. Hard-delete all rancher/k3s data directories
sudo rm -rf /var/lib/rancher /etc/rancher
sudo rm -rf /var/lib/rancher/k3s-stream /var/lib/kubelet-stream
sudo rm -rf /var/lib/rancher/k3s-batch /var/lib/kubelet-batch
sudo rm -rf /run/k3s /run/flannel

# 1d. Remove worker network namespace bridge artifacts
sudo ip link delete k3s-br0 2>/dev/null || true
sudo ip netns delete ns-worker-stream 2>/dev/null || true
sudo ip netns delete ns-worker-batch 2>/dev/null || true

# 1e. Flush iptables NAT rules from old bootstrap
sudo iptables -t nat -D POSTROUTING -s 10.200.0.0/24 ! -o k3s-br0 -j MASQUERADE 2>/dev/null || true
sudo iptables -D FORWARD -i k3s-br0 -j ACCEPT 2>/dev/null || true
sudo iptables -D FORWARD -o k3s-br0 -j ACCEPT 2>/dev/null || true

# 1f. Remove old kubeconfig
rm -f ~/.kube/config
```

**Verify wipe is clean:**
```bash
pgrep -a k3s   # expect: no output
ip netns list  # expect: no ns-worker-* entries
ls /var/lib/rancher 2>/dev/null || echo "CLEAN -- rancher dir gone"
```

---

## Phase 2: Fresh Single-Node Bootstrap

> Estimate 5 minutes. Run infra/bootstrap/host-bootstrap-single.sh (new script).

Key differences from old 3-node bootstrap:
- No network namespaces, no veth pairs, no bridge k3s-br0
- No k3s agent systemd services
- Both workload=streaming AND workload=batch labels go on the single node
- No iptables NAT masquerade rules

```bash
# Install k3s in server mode (no external agents)
sudo mkdir -p /etc/rancher/k3s
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server \
  --disable=traefik \
  --node-name=k3s-node \
  --kube-apiserver-arg=service-node-port-range=30000-40000 \
  --write-kubeconfig-mode=644 \
  --secrets-encryption" sh -

# Wait for node Ready
until kubectl get nodes 2>/dev/null | grep -q "Ready"; do sleep 2; done

# Apply BOTH role labels to single node (manifests unchanged)
kubectl label node k3s-node \
  node-role.kubernetes.io/worker=worker \
  node-role.kubernetes.io/streaming=streaming \
  node-role.kubernetes.io/batch=batch \
  workload=streaming \
  --overwrite

# Configure local-path provisioner
sudo mkdir -p /data/k3s-storage && sudo chmod 777 /data/k3s-storage
kubectl -n kube-system patch cm local-path-config --type=merge \
  -p '{"data":{"config.json":"{\"nodePathMap\":[{\"node\":\"DEFAULT_PATH_FOR_NON_LISTED_NODES\",\"paths\":[\"/data/k3s-storage\"]}]}"}}'

# Configure kubeconfig
mkdir -p ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown "$(id -u):$(id -g)" ~/.kube/config
chmod 600 ~/.kube/config
kubectl config rename-context default k3s-data-platform 2>/dev/null || true
```

---

## CHECKPOINT: Cluster Health Verification

> Human action required. Verify before proceeding to Phase 3.

```bash
kubectl get nodes -L workload -o wide    # 1 node, Ready, workload=streaming
kubectl cluster-info                     # API server reachable
free -h                                  # RAM headroom improved (~1.5 GB freed vs before)
kubectl get pods -A                      # Only system pods running
```

---

## Phase 3: Manifest Patches

> Estimate 30 minutes.

### 3.1 StorageClass -- Replace Longhorn with local-path

```bash
# Find all PVCs using longhorn
grep -r "longhorn" k8s/ --include="*.yaml" -l

# Replace storageClassName
find k8s/ -name "*.yaml" -exec sed -i \
  's/storageClassName: longhorn-isolated/storageClassName: local-path/g' {} \;
find k8s/ -name "*.yaml" -exec sed -i \
  's/storageClassName: longhorn/storageClassName: local-path/g' {} \;
```

### 3.2 NodeSelector -- No changes needed

All existing nodeSelector: {workload: streaming} and nodeSelector: {workload: batch} schedule
correctly because both labels are on k3s-node.

### 3.3 Remove Longhorn, Loki, Promtail, Jaeger from ArgoCD sync

```bash
# Find and disable/delete their Application resources in argocd/dev/
grep -r "loki\|promtail\|jaeger\|longhorn" argocd/ --include="*.yaml" -l
# Options: delete the Application YAML files, or add sync-options: Prune=false annotation
```

### 3.4 NetworkPolicy -- Remove inter-node bridge IPs

```bash
# Check for old bridge subnet references
grep -r "10.200.0" k8s/ --include="*.yaml" -l
# Replace any ipBlock 10.200.0.x rules with pod/namespace selectors
```

---

## Phase 4: Re-apply Platform via ArgoCD

> Estimate 15 minutes. Standard GitOps re-sync.

```bash
# Commit all manifest changes
git add k8s/ argocd/ infra/
git commit -m "chore(infra): migrate to single-node k3s, replace Longhorn with local-path, defer Loki/Jaeger"
git push

# Bootstrap ArgoCD onto fresh cluster
kubectl apply -k argocd/install/ 2>/dev/null || \
  kubectl apply -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/core-install.yaml

kubectl -n argocd wait --for=condition=available deploy/argocd-server --timeout=120s

# Trigger sync
kubectl -n argocd get applications -o name | \
  xargs -I{} kubectl -n argocd annotate {} argocd.argoproj.io/refresh=normal
```

---

## Phase 5: Validate Platform Stack

```bash
# All pods running (no OOMKill)
kubectl get pods -A | grep -Ev "Running|Completed"

# Memory headroom
kubectl top nodes
free -h

# Smoke tests
curl -s http://localhost:30080/health | jq .     # Kong
kubectl exec -n platform deploy/redpanda -- rpk cluster info  # Redpanda
curl -s http://localhost:8081/overview | jq .    # Flink (after port-forward)
kubectl -n argocd get applications               # ArgoCD sync status
```

---

## Phase 6: Documentation Update

Update these files to reflect the new architecture:

### NOTES.md changes
- Section "Kubernetes Environment (3-Node Multi-Node Simulation)" -> "Single-Node k3s Cluster"
- Nodes: remove k3s-control-plane, k3s-worker-stream, k3s-worker-batch
- Add: k3s-node: Single node, all workloads (control-plane + streaming + batch)
- Memory table: remove Longhorn (512 MiB), Loki+Promtail (160 MiB), Jaeger (128 MiB)
- Update total baseline from ~3.8 GB to ~2.7 GB

### CONTEXT.md changes
- Section 8 "Host Bootstrap": update to describe single-node k3s with no netns workers

### infra/bootstrap/ changes
- Create host-bootstrap-single.sh (canonical single-node bootstrap)
- Retired legacy 3-node bootstrap and virtual netns bridge scripts

---

## Definition of Done

- [ ] k9s shows 1 node k3s-node in Ready state
- [ ] free -h shows at least 3 GB RAM available (vs ~800 MB before)
- [ ] No OOMKilled pods in kubectl get pods -A
- [ ] All retained services Running: Kong, Redpanda, Flink, MinIO, Argo Workflows, ArgoCD, Prometheus, Grafana, Vault
- [ ] ArgoCD shows all Applications Synced + Healthy (except deferred: Loki, Jaeger, Longhorn)
- [ ] NOTES.md memory table updated (~2.7 GB new baseline)
- [ ] host-bootstrap-single.sh created and tested end-to-end
- [ ] No manifest references to longhorn-isolated, 10.200.0.x bridge IPs
- [ ] kubectl context still named k3s-data-platform
