#!/usr/bin/env bash
# ==============================================================================
# Cloud-Native Data Platform - 3-Node k3s Host Bootstrap Script
# Target Host OS: WSL2 (AlmaLinux-10) or Bare-Metal Enterprise Linux
# No Docker-in-Docker.
# ==============================================================================

set -euo pipefail

CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

log_info() { echo -e "${CYAN}[INFO]${NC} $1"; }
log_ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_err()  { echo -e "${RED}[ERROR]${NC} $1"; }

echo "========================================================================"
echo "  Cloud-Native Data Platform: 3-Node k3s Cluster Bootstrap"
echo "  Nodes: k3s-control-plane, k3s-worker-stream, k3s-worker-batch"
echo "  Storage Pool: /data/k3s-storage (Dedicated isolated mount)"
echo "========================================================================"

# 1. Verify systemd is running as PID 1
log_info "Verifying systemd init system..."
if [ "$(ps -p 1 -o comm=)" != "systemd" ]; then
    log_err "systemd is not PID 1. Please enable systemd in /etc/wsl.conf and restart WSL."
    exit 1
fi
log_ok "systemd is active as PID 1."

# Disable swap (Kubernetes best practice for deterministic memory limits)
sudo swapoff -a 2>/dev/null || true

# 2. Create isolated storage directory and ensure shared mount propagation
log_info "Ensuring /data/k3s-storage exists and has proper permissions..."
sudo mkdir -p /data/k3s-storage
sudo chmod 777 /data/k3s-storage
sudo mount --make-rshared /
log_ok "Isolated storage pool prepared at /data/k3s-storage and root mount marked shared."

# 3. Install k3s control plane (server) if not installed
#
# --secrets-encryption: Enables AES-GCM encryption of Kubernetes Secret objects
# at rest in the datastore (SQLite). Required so that vault-unseal-keys and other
# K8s Secrets are not stored plaintext on disk.
# Key file: /var/lib/rancher/k3s/server/cred/encryption-config.json
#
if ! command -v k3s &> /dev/null; then
    log_info "Installing k3s server (control-plane) with secrets encryption and custom NodePort range..."
    sudo mkdir -p /etc/rancher/k3s
    curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server \
      --disable=traefik \
      --node-name=k3s-control-plane \
      --kube-apiserver-arg=service-node-port-range=30000-40000 \
      --write-kubeconfig-mode=644 \
      --secrets-encryption" sh -
    log_ok "k3s server installed with built-in local-storage and secrets encryption."
else
    log_info "k3s binary already installed. Ensuring k3s service is active..."
    if sudo grep -qr "secrets-encryption" /etc/rancher/k3s/ 2>/dev/null || \
       sudo test -f /var/lib/rancher/k3s/server/cred/encryption-config.json; then
        log_ok "Secrets encryption already active."
    else
        log_warn "Secrets encryption NOT active on existing cluster."
        log_warn "To enable on an existing cluster, see: docs/infra/etcd-encryption.md"
        log_warn "Proceeding without modifying existing installation."
    fi
    sudo chmod 644 /etc/rancher/k3s/k3s.yaml 2>/dev/null || true
    sudo systemctl restart k3s
fi

# Ensure k3s and kubectl symlinks exist in /usr/bin for sudo secure_path compatibility
sudo ln -sf /usr/local/bin/k3s /usr/bin/k3s
sudo ln -sf /usr/local/bin/k3s /usr/bin/kubectl

# Wait for k3s control plane to become ready
log_info "Waiting for k3s control plane to initialize..."
until sudo /usr/local/bin/k3s kubectl get nodes 2>/dev/null | grep -q "k3s-control-plane"; do
    sleep 2
done
log_ok "k3s-control-plane is running."

# 4. Extract token for worker nodes
NODE_TOKEN=$(sudo cat /var/lib/rancher/k3s/server/node-token)

# 5. Provision Network Bridge and Namespaces for Worker Nodes
log_info "Setting up isolated network namespaces and bridge for worker nodes..."

# Ensure iptables is available for bridge NAT
if ! command -v iptables &>/dev/null; then
    log_info "Installing iptables-nft for worker network bridge NAT..."
    sudo dnf install -y iptables-nft >/dev/null 2>&1 || true
fi

# Enable IPv4 forwarding
sudo sysctl -w net.ipv4.ip_forward=1 >/dev/null

# Setup bridge k3s-br0
if ! ip link show k3s-br0 &>/dev/null; then
    sudo ip link add name k3s-br0 type bridge
    sudo ip addr add 10.200.0.1/24 dev k3s-br0
    sudo ip link set k3s-br0 up
fi

# Configure iptables forwarding & NAT masquerade
sudo iptables -C FORWARD -i k3s-br0 -j ACCEPT 2>/dev/null || sudo iptables -A FORWARD -i k3s-br0 -j ACCEPT
sudo iptables -C FORWARD -o k3s-br0 -j ACCEPT 2>/dev/null || sudo iptables -A FORWARD -o k3s-br0 -j ACCEPT
sudo iptables -t nat -C POSTROUTING -s 10.200.0.0/24 ! -o k3s-br0 -j MASQUERADE 2>/dev/null || \
    sudo iptables -t nat -A POSTROUTING -s 10.200.0.0/24 ! -o k3s-br0 -j MASQUERADE

setup_worker_netns() {
    local NS_NAME="$1"
    local VETH_HOST="$2"
    local VETH_NS="$3"
    local NODE_IP="$4"

    if ! sudo ip netns list | grep -qw "$NS_NAME"; then
        sudo ip netns add "$NS_NAME"
    fi
    sudo ip netns exec "$NS_NAME" ip link set lo up

    if ! ip link show "$VETH_HOST" &>/dev/null; then
        sudo ip link add "$VETH_HOST" type veth peer name "$VETH_NS"
        sudo ip link set "$VETH_HOST" master k3s-br0
        sudo ip link set "$VETH_HOST" up
        sudo ip link set "$VETH_NS" netns "$NS_NAME"
        sudo ip netns exec "$NS_NAME" ip link set "$VETH_NS" name eth0
        sudo ip netns exec "$NS_NAME" ip addr add "$NODE_IP/24" dev eth0
        sudo ip netns exec "$NS_NAME" ip link set eth0 up
        sudo ip netns exec "$NS_NAME" ip route replace default via 10.200.0.1
    fi
}

setup_worker_netns ns-worker-stream veth-st-host veth-st-ns 10.200.0.2
setup_worker_netns ns-worker-batch veth-bt-host veth-bt-ns 10.200.0.3

# Prepare isolated directories
sudo mkdir -p /var/lib/rancher/k3s-stream/{data,run/flannel,run/k3s} /var/lib/kubelet-stream
sudo mkdir -p /var/lib/rancher/k3s-batch/{data,run/flannel,run/k3s} /var/lib/kubelet-batch

log_ok "Isolated network namespaces prepared (ns-worker-stream: 10.200.0.2, ns-worker-batch: 10.200.0.3)."

# 6. Configure Worker 1: k3s-worker-stream (Streaming Workload Node)
log_info "Configuring k3s-worker-stream agent service..."
sudo bash -c "cat <<'SYSTEMD' > /etc/systemd/system/k3s-worker-stream.service
[Unit]
Description=k3s-worker-stream agent
After=network.target k3s.service
Wants=k3s.service

[Service]
Type=exec
Slice=k3sstream.slice
NetworkNamespacePath=/run/netns/ns-worker-stream
PrivateMounts=yes
BindPaths=/var/lib/rancher/k3s-stream/run/flannel:/run/flannel
BindPaths=/var/lib/rancher/k3s-stream/run/k3s:/run/k3s
BindPaths=/var/lib/kubelet-stream:/var/lib/kubelet
KillMode=process
Delegate=yes
LimitNOFILE=1048576
LimitNPROC=infinity
LimitCORE=infinity
TasksMax=infinity
TimeoutStartSec=0
Restart=always
RestartSec=5
ExecStart=/usr/local/bin/k3s agent \
  --server=https://10.200.0.1:6443 \
  --token=${NODE_TOKEN} \
  --node-name=k3s-worker-stream \
  --node-label workload=streaming \
  --node-ip=10.200.0.2 \
  --data-dir=/var/lib/rancher/k3s-stream/data \
  --kubelet-arg=cgroup-root=/k3sstream

[Install]
WantedBy=multi-user.target
SYSTEMD"

# 7. Configure Worker 2: k3s-worker-batch (Batch Workload Node)
log_info "Configuring k3s-worker-batch agent service..."
sudo bash -c "cat <<'SYSTEMD' > /etc/systemd/system/k3s-worker-batch.service
[Unit]
Description=k3s-worker-batch agent
After=network.target k3s.service
Wants=k3s.service

[Service]
Type=exec
Slice=k3sbatch.slice
NetworkNamespacePath=/run/netns/ns-worker-batch
PrivateMounts=yes
BindPaths=/var/lib/rancher/k3s-batch/run/flannel:/run/flannel
BindPaths=/var/lib/rancher/k3s-batch/run/k3s:/run/k3s
BindPaths=/var/lib/kubelet-batch:/var/lib/kubelet
KillMode=process
Delegate=yes
LimitNOFILE=1048576
LimitNPROC=infinity
LimitCORE=infinity
TasksMax=infinity
TimeoutStartSec=0
Restart=always
RestartSec=5
ExecStart=/usr/local/bin/k3s agent \
  --server=https://10.200.0.1:6443 \
  --token=${NODE_TOKEN} \
  --node-name=k3s-worker-batch \
  --node-label workload=batch \
  --node-ip=10.200.0.3 \
  --data-dir=/var/lib/rancher/k3s-batch/data \
  --kubelet-arg=cgroup-root=/k3sbatch

[Install]
WantedBy=multi-user.target
SYSTEMD"

# Enable and start agent services
sudo systemctl daemon-reload
sudo systemctl enable --now k3s-worker-stream.service
sudo systemctl enable --now k3s-worker-batch.service
log_ok "Worker agent services started."

# 8. Configure kubeconfig for current user
sudo chmod 644 /etc/rancher/k3s/k3s.yaml
mkdir -p "$HOME/.kube"
sudo cp /etc/rancher/k3s/k3s.yaml "$HOME/.kube/config"
sudo chown "$(id -u):$(id -g)" "$HOME/.kube/config"
chmod 600 "$HOME/.kube/config"
export KUBECONFIG="$HOME/.kube/config"

# If run under sudo, also sync kubeconfig to the calling non-root user
if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
    USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
    if [ -n "$USER_HOME" ] && [ -d "$USER_HOME" ]; then
        mkdir -p "$USER_HOME/.kube"
        sudo cp /etc/rancher/k3s/k3s.yaml "$USER_HOME/.kube/config"
        sudo chown -R "$SUDO_USER:$(id -g "$SUDO_USER")" "$USER_HOME/.kube"
        sudo chmod 600 "$USER_HOME/.kube/config"
        log_ok "kubeconfig synced to $USER_HOME/.kube/config for user $SUDO_USER"
    fi
fi

# Rename the default context to something descriptive
kubectl config rename-context default k3s-data-platform 2>/dev/null || true
kubectl config use-context k3s-data-platform 2>/dev/null || true
log_ok "kubeconfig written: $HOME/.kube/config  (context: k3s-data-platform)"

# Persist KUBECONFIG in shell profiles so new terminals pick it up automatically.
# The 'export' above only affects this script's subshell — it dies when the script exits.
KUBECONFIG_EXPORT='export KUBECONFIG="$HOME/.kube/config"'
for PROFILE in "$HOME/.bashrc" "$HOME/.zshrc"; do
    if [ -f "$PROFILE" ] && ! grep -q 'KUBECONFIG.*\.kube/config' "$PROFILE"; then
        echo "" >> "$PROFILE"
        echo "# k3s kubeconfig (added by host-bootstrap.sh)" >> "$PROFILE"
        echo "$KUBECONFIG_EXPORT" >> "$PROFILE"
        log_ok "KUBECONFIG persisted in $PROFILE"
    fi
done
log_warn "Run: source ~/.bashrc  (or open a new terminal) to activate KUBECONFIG in your current session."

# 9. Wait for all 3 nodes to report Ready
log_info "Waiting for all 3 nodes to report Ready status..."
MAX_ATTEMPTS=40
READY_COUNT=0
for i in $(seq 1 $MAX_ATTEMPTS); do
    READY_COUNT=$(sudo /usr/local/bin/k3s kubectl get nodes --no-headers 2>/dev/null | grep -c "Ready" || true)
    if [ "$READY_COUNT" -ge 3 ]; then
        echo ""
        log_ok "All 3 nodes are in Ready status."
        break
    fi
    echo -ne "  Attempt $i/$MAX_ATTEMPTS: $READY_COUNT/3 nodes Ready...\r"
    sleep 3
done

if [ "$READY_COUNT" -lt 3 ]; then
    echo ""
    log_err "CRITICAL: Timeout waiting for 3 nodes to become Ready ($READY_COUNT/3 ready)."
    log_err "Current node list:"
    sudo /usr/local/bin/k3s kubectl get nodes || true
    echo ""
    log_err "Investigating worker failures. Checking worker stream logs:"
    sudo journalctl -u k3s-worker-stream.service -n 20 --no-pager || true
    exit 1
fi

# 10. Label node roles via control-plane API (NodeRestriction forbids self-labeling by agents)
log_info "Applying official Kubernetes node roles to worker nodes..."
sudo /usr/local/bin/k3s kubectl label node k3s-worker-stream node-role.kubernetes.io/worker=worker node-role.kubernetes.io/streaming=streaming --overwrite
sudo /usr/local/bin/k3s kubectl label node k3s-worker-batch node-role.kubernetes.io/worker=worker node-role.kubernetes.io/batch=batch --overwrite
log_ok "Node roles successfully applied."

# 11. Verify secrets encryption is active
log_info "Verifying secrets encryption at rest..."
ENCRYPTION_CONFIG="/var/lib/rancher/k3s/server/cred/encryption-config.json"
if sudo test -f "$ENCRYPTION_CONFIG"; then
    PROVIDER=$(sudo cat "$ENCRYPTION_CONFIG" | grep -o '"name":"[^"]*"' | head -1 | cut -d'"' -f4)
    log_ok "Secrets encryption active. Provider: ${PROVIDER:-aescbc/aesgcm}"
    log_ok "Encryption config: ${ENCRYPTION_CONFIG}"
else
    log_warn "Encryption config not found at ${ENCRYPTION_CONFIG}."
    log_warn "Secrets may not be encrypted at rest. See: docs/infra/etcd-encryption.md"
fi

# 12. Configure built-in local-path storage to use /data/k3s-storage and create compatibility alias
log_info "Configuring built-in local-path provisioner to use /data/k3s-storage..."
sudo /usr/local/bin/k3s kubectl -n kube-system patch cm local-path-config --type=merge -p '{"data":{"config.json":"{\"nodePathMap\":[{\"node\":\"DEFAULT_PATH_FOR_NON_LISTED_NODES\",\"paths\":[\"/data/k3s-storage\"]}]}"}}' 2>/dev/null || true
sudo /usr/local/bin/k3s kubectl -n kube-system rollout restart deploy/local-path-provisioner 2>/dev/null || true

cat <<'SC' | sudo /usr/local/bin/k3s kubectl apply -f - 2>/dev/null || true
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: longhorn-isolated
provisioner: rancher.io/local-path
volumeBindingMode: WaitForFirstConsumer
reclaimPolicy: Delete
SC
log_ok "Built-in local-path storage configured at /data/k3s-storage."

echo ""
log_ok "3-Node cluster successfully verified from live Kubernetes state!"
echo "========================================================================"
sudo /usr/local/bin/k3s kubectl get nodes -L workload -o wide
echo "========================================================================"
