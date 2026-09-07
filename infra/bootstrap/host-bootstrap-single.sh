#!/usr/bin/env bash
# ==============================================================================
# Cloud-Native Data Platform - Single-Node k3s Host Bootstrap Script
# Target Host OS: WSL2 (AlmaLinux-10) or Bare-Metal Enterprise Linux
#
# Architecture: 1 k3s process (server mode, no external agents)
#   - Control-plane + all workloads run on a single node (k3s-node)
#   - Both workload=streaming and workload=batch labels applied to the single node
#   - nodeSelector in existing manifests continues to work unchanged
#   - No network namespaces, no bridge, no iptables NAT for workers
#   - kubectl context: k3s-data-platform (unchanged from 3-node)
#
# Memory savings vs 3-node: ~1.5 GB (3x kubelet+flannel+CoreDNS -> 1 of each)
# Total platform baseline: ~2.7 GB (vs ~3.8 GB for 3-node)
#
# EKS compatibility: manifests are identical; nodeSelectors work on real EKS nodes.
# ==============================================================================

set -euo pipefail

CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info() { echo -e "${CYAN}[INFO]${NC} $1"; }
log_ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_err()  { echo -e "${RED}[ERROR]${NC} $1"; }

echo "========================================================================"
echo "  Cloud-Native Data Platform: Single-Node k3s Cluster Bootstrap"
echo "  Node: k3s-node (control-plane + streaming + batch workloads)"
echo "  Storage Pool: /data/k3s-storage (local-path provisioner)"
echo "========================================================================"

# 1. Verify systemd is running as PID 1
log_info "Verifying systemd init system..."
if [ "$(ps -p 1 -o comm=)" != "systemd" ]; then
    log_err "systemd is not PID 1. Enable systemd in /etc/wsl.conf and restart WSL."
    exit 1
fi
log_ok "systemd is active as PID 1."

# Disable swap (Kubernetes best practice for deterministic memory limits)
sudo swapoff -a 2>/dev/null || true

# 2. Create isolated storage directory
log_info "Ensuring /data/k3s-storage exists with proper permissions..."
sudo mkdir -p /data/k3s-storage
sudo chmod 777 /data/k3s-storage
sudo mount --make-rshared / 2>/dev/null || true
log_ok "Storage pool prepared at /data/k3s-storage."

# 3. Install k3s server (single-node: server mode handles scheduling too)
#
# --disable=traefik:              Use Kong Gateway instead of Traefik
# --node-name=k3s-node:           Single canonical node name
# --secrets-encryption:           AES-GCM encryption of K8s Secrets at rest
# --kube-apiserver-arg:           Extend NodePort range to 30000-40000
#
# Detection logic:
#   a) No k3s binary at all               -> fresh install
#   b) k3s binary present, no k3s.service -> reinstall (post-teardown state)
#   c) k3s binary present, wrong nodename -> uninstall + reinstall
#   d) k3s binary present, k3s-node name  -> daemon-reload + restart
#
K3S_EXEC_ARGS="server --disable=traefik --node-name=k3s-node --kube-apiserver-arg=service-node-port-range=30000-40000 --write-kubeconfig-mode=644 --secrets-encryption"

_do_k3s_install() {
    log_info "Installing k3s server (single-node) with secrets encryption..."
    sudo mkdir -p /etc/rancher/k3s
    export INSTALL_K3S_EXEC="${K3S_EXEC_ARGS}"
    curl -sfL https://get.k3s.io | sh -s - ${K3S_EXEC_ARGS}
    unset INSTALL_K3S_EXEC
    log_ok "k3s installed with node name k3s-node."
}

if ! command -v k3s &>/dev/null; then
    # Case (a): binary absent — fresh install
    _do_k3s_install
elif ! sudo systemctl is-enabled k3s &>/dev/null 2>&1; then
    # Case (b): binary present but service missing (post-teardown, teardown removes
    # the service but leaves the binary). Reinstall to recreate the systemd unit.
    log_warn "k3s binary found but k3s.service is absent (post-teardown state)."
    log_warn "Running installer to recreate the systemd unit..."
    _do_k3s_install
else
    # Binary present AND service present. Check node name.
    EXISTING_NODE=$(sudo /usr/local/bin/k3s kubectl get nodes --no-headers 2>/dev/null | awk '{print $1}' | head -1)
    if [ -n "${EXISTING_NODE}" ] && [ "${EXISTING_NODE}" != "k3s-node" ]; then
        # Case (c): wrong node name (old 3-node remnant) — full reinstall
        log_warn "Node name is '${EXISTING_NODE}' (expected k3s-node). Performing reinstall..."
        sudo k3s-uninstall.sh 2>/dev/null || true
        sudo rm -rf /var/lib/rancher /etc/rancher /run/k3s
        _do_k3s_install
    else
        # Case (d): already correct — reload + restart
        log_info "k3s already configured correctly. Restarting service..."
        sudo chmod 644 /etc/rancher/k3s/k3s.yaml 2>/dev/null || true
        sudo systemctl daemon-reload
        sudo systemctl restart k3s
        log_ok "k3s service restarted."
    fi
fi

# Ensure k3s and kubectl symlinks exist in /usr/bin for sudo secure_path
sudo ln -sf /usr/local/bin/k3s /usr/bin/k3s
sudo ln -sf /usr/local/bin/k3s /usr/bin/kubectl

# 4. Wait for k3s-node to become Ready
log_info "Waiting for k3s-node to initialize and become Ready..."
until sudo /usr/local/bin/k3s kubectl get nodes 2>/dev/null | grep -q "k3s-node"; do
    sleep 2
done
log_ok "k3s-node is registered with the API server."

until sudo /usr/local/bin/k3s kubectl get nodes 2>/dev/null | grep "k3s-node" | grep -q "Ready"; do
    echo -ne "  Waiting for k3s-node Ready status...\r"
    sleep 2
done
echo ""
log_ok "k3s-node is Ready."

# 5. Apply node labels for workload scheduling
log_info "Applying node role and workload labels to k3s-node..."
sudo /usr/local/bin/k3s kubectl label node k3s-node \
  node-role.kubernetes.io/control-plane="true" \
  node-role.kubernetes.io/master="true" \
  node-role.kubernetes.io/worker=worker \
  node-role.kubernetes.io/streaming=streaming \
  node-role.kubernetes.io/batch=batch \
  workload=single-node \
  --overwrite
log_ok "Node labels applied: control-plane, worker, streaming, batch"

# 6. Configure kubeconfig and sync contexts
sudo chmod 644 /etc/rancher/k3s/k3s.yaml
sudo /usr/local/bin/k3s kubectl config rename-context default k3s-data-platform --kubeconfig /etc/rancher/k3s/k3s.yaml 2>/dev/null || true
sudo /usr/local/bin/k3s kubectl config use-context k3s-data-platform --kubeconfig /etc/rancher/k3s/k3s.yaml 2>/dev/null || true

_install_kubeconfig_for() {
    local target_user="$1"
    local target_home
    target_home=$(getent passwd "$target_user" 2>/dev/null | cut -d: -f6)
    if [ -n "$target_home" ] && [ -d "$target_home" ]; then
        mkdir -p "$target_home/.kube"
        sudo cp /etc/rancher/k3s/k3s.yaml "$target_home/.kube/config"
        sudo chown -R "$target_user:$(id -g "$target_user")" "$target_home/.kube"
        sudo chmod 600 "$target_home/.kube/config"
        log_ok "kubeconfig installed for $target_user at $target_home/.kube/config"
    fi
}

_install_kubeconfig_for "$(id -un)"
[ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ] && _install_kubeconfig_for "$SUDO_USER"
id "x" &>/dev/null && [ "$(id -un)" != "x" ] && _install_kubeconfig_for "x"

export KUBECONFIG="$HOME/.kube/config"
log_ok "kubeconfig configured with context: k3s-data-platform"

# Persist KUBECONFIG in shell profiles
KUBECONFIG_EXPORT='export KUBECONFIG="$HOME/.kube/config"'
for PROFILE in "$HOME/.bashrc" "$HOME/.zshrc"; do
    if [ -f "$PROFILE" ] && ! grep -q 'KUBECONFIG.*\.kube/config' "$PROFILE"; then
        echo "" >> "$PROFILE"
        echo "# k3s kubeconfig (added by host-bootstrap-single.sh)" >> "$PROFILE"
        echo "$KUBECONFIG_EXPORT" >> "$PROFILE"
        log_ok "KUBECONFIG persisted in $PROFILE"
    fi
done

# 7. Configure local-path provisioner to use /data/k3s-storage
log_info "Configuring local-path provisioner storage root to /data/k3s-storage..."
log_info "Waiting for local-path-config ConfigMap to be ready..."
until sudo /usr/local/bin/k3s kubectl -n kube-system get cm local-path-config &>/dev/null; do
    sleep 2
done
sudo /usr/local/bin/k3s kubectl -n kube-system patch cm local-path-config --type=merge \
    -p '{"data":{"config.json":"{\"nodePathMap\":[{\"node\":\"DEFAULT_PATH_FOR_NON_LISTED_NODES\",\"paths\":[\"/data/k3s-storage\"]}]}"}}' 2>/dev/null || true
sudo /usr/local/bin/k3s kubectl -n kube-system rollout restart deploy/local-path-provisioner 2>/dev/null || true
log_ok "local-path provisioner configured at /data/k3s-storage."

# 8. Verify secrets encryption is active
log_info "Verifying secrets encryption at rest..."
ENCRYPTION_CONFIG="/var/lib/rancher/k3s/server/cred/encryption-config.json"
if sudo test -f "$ENCRYPTION_CONFIG"; then
    PROVIDER=$(sudo cat "$ENCRYPTION_CONFIG" | grep -o '"name":"[^"]*"' | head -1 | cut -d'"' -f4)
    log_ok "Secrets encryption active. Provider: ${PROVIDER:-aescbc/aesgcm}"
else
    log_warn "Encryption config not found at ${ENCRYPTION_CONFIG}."
    log_warn "Secrets may not be encrypted at rest."
fi

# 9. Final cluster state report
echo ""
log_ok "Single-node k3s cluster bootstrap complete!"
echo "========================================================================"
sudo /usr/local/bin/k3s kubectl get nodes -L workload,node-role.kubernetes.io/streaming,node-role.kubernetes.io/batch -o wide
echo "========================================================================"
echo ""
echo "  Next steps:"
echo "  1. Verify cluster:       kubectl get nodes && kubectl get pods -A"
echo "  2. Apply ArgoCD root:    kubectl apply -f argocd/dev/root.yaml"
echo "  3. Check memory:         free -h"
echo "  4. Run smoke tests:      make verify"
echo ""
log_warn "Run: source ~/.bashrc  (or open a new terminal) to activate KUBECONFIG."