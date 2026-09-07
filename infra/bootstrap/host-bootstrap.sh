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

# 2. Create isolated storage directory
log_info "Ensuring /data/k3s-storage exists and has proper permissions..."
sudo mkdir -p /data/k3s-storage
sudo chmod 777 /data/k3s-storage
log_ok "Isolated storage pool prepared at /data/k3s-storage."

# 3. Install k3s control plane (server) if not installed
#
# --secrets-encryption: Enables AES-GCM encryption of Kubernetes Secret objects
# at rest in the datastore (SQLite). Required so that vault-unseal-keys and other
# K8s Secrets are not stored plaintext on disk.
# Key file: /var/lib/rancher/k3s/server/cred/encryption-config.json
#
if ! command -v k3s &> /dev/null; then
    log_info "Installing k3s server (control-plane) with secrets encryption enabled..."
    curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server \
      --disable=traefik \
      --disable=local-storage \
      --node-name=k3s-control-plane \
      --secrets-encryption" sh -
    log_ok "k3s server installed with secrets encryption."
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
    sudo systemctl restart k3s
fi

# Wait for k3s control plane to become ready
log_info "Waiting for k3s control plane to initialize..."
until sudo k3s kubectl get nodes 2>/dev/null | grep -q "k3s-control-plane"; do
    sleep 2
done
log_ok "k3s-control-plane is running."

# 4. Extract token for worker nodes
NODE_TOKEN=$(sudo cat /var/lib/rancher/k3s/server/node-token)

# 5. Configure Worker 1: k3s-worker-stream (Streaming Workload Node)
log_info "Configuring k3s-worker-stream agent service..."
sudo bash -c "cat <<'SYSTEMD' > /etc/systemd/system/k3s-worker-stream.service
[Unit]
Description=k3s-worker-stream agent
After=network.target k3s.service

[Service]
Type=exec
ExecStart=/usr/local/bin/k3s agent --server=https://127.0.0.1:6443 --token=${NODE_TOKEN} --node-name=k3s-worker-stream --node-label workload=streaming
Restart=always
RestartSec=5
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
SYSTEMD"

# 6. Configure Worker 2: k3s-worker-batch (Batch Workload Node)
log_info "Configuring k3s-worker-batch agent service..."
sudo bash -c "cat <<'SYSTEMD' > /etc/systemd/system/k3s-worker-batch.service
[Unit]
Description=k3s-worker-batch agent
After=network.target k3s.service

[Service]
Type=exec
ExecStart=/usr/local/bin/k3s agent --server=https://127.0.0.1:6443 --token=${NODE_TOKEN} --node-name=k3s-worker-batch --node-label workload=batch
Restart=always
RestartSec=5
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
SYSTEMD"

# Enable and start agent services
sudo systemctl daemon-reload
sudo systemctl enable --now k3s-worker-stream.service
sudo systemctl enable --now k3s-worker-batch.service
log_ok "Worker agent services started."

# 7. Configure kubeconfig for current user
mkdir -p "$HOME/.kube"
sudo cp /etc/rancher/k3s/k3s.yaml "$HOME/.kube/config"
sudo chown "$(id -u):$(id -g)" "$HOME/.kube/config"
export KUBECONFIG="$HOME/.kube/config"
log_ok "kubeconfig written to $HOME/.kube/config."

# 8. Wait for all 3 nodes to report Ready
log_info "Waiting for all 3 nodes to report Ready status..."
for i in {1..30}; do
    READY_COUNT=$(sudo k3s kubectl get nodes --no-headers 2>/dev/null | grep -c "Ready" || true)
    if [ "$READY_COUNT" -ge 3 ]; then
        break
    fi
    sleep 3
done

# 9. Verify secrets encryption is active
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

echo ""
log_ok "3-Node cluster successfully bootstrapped!"
sudo k3s kubectl get nodes -o wide --show-labels
echo ""
echo "========================================================================"
echo "  Control Plane: k3s-control-plane"
echo "  Worker 1:      k3s-worker-stream  (Label: workload=streaming)"
echo "  Worker 2:      k3s-worker-batch   (Label: workload=batch)"
echo "  Storage Pool:  /data/k3s-storage"
echo "  Encryption:    Kubernetes Secrets encrypted at rest (AES-GCM)"
echo "========================================================================"
