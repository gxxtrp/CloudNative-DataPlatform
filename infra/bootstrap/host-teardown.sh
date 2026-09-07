#!/usr/bin/env bash
# ==============================================================================
# Cloud-Native Data Platform - 3-Node k3s Host Teardown Script
# ==============================================================================

set -euo pipefail

echo "Stopping and tearing down 3-node k3s cluster..."

# 1. Stop and disable worker agent services
sudo systemctl stop k3s-worker-stream.service 2>/dev/null || true
sudo systemctl disable k3s-worker-stream.service 2>/dev/null || true
sudo rm -f /etc/systemd/system/k3s-worker-stream.service

sudo systemctl stop k3s-worker-batch.service 2>/dev/null || true
sudo systemctl disable k3s-worker-batch.service 2>/dev/null || true
sudo rm -f /etc/systemd/system/k3s-worker-batch.service

sudo systemctl daemon-reload

# 2. Clean up worker network namespaces and virtual bridge
echo "Cleaning up worker network namespaces and virtual bridge..."
sudo ip netns del ns-worker-stream 2>/dev/null || true
sudo ip netns del ns-worker-batch 2>/dev/null || true

if ip link show k3s-br0 &>/dev/null; then
    sudo ip link del k3s-br0 2>/dev/null || true
fi

# Clean up iptables NAT and forwarding rules
if command -v iptables &>/dev/null; then
    sudo iptables -D FORWARD -i k3s-br0 -j ACCEPT 2>/dev/null || true
    sudo iptables -D FORWARD -o k3s-br0 -j ACCEPT 2>/dev/null || true
    sudo iptables -t nat -D POSTROUTING -s 10.200.0.0/24 ! -o k3s-br0 -j MASQUERADE 2>/dev/null || true
fi

# 3. Uninstall k3s server (stops server daemon and cleans up k3s system mounts)
if [ -f /usr/local/bin/k3s-uninstall.sh ]; then
    echo "Uninstalling k3s server..."
    sudo /usr/local/bin/k3s-uninstall.sh || true
fi

# 4. Unmount any remaining container and kubelet mounts
echo "Unmounting leftover container and kubelet mounts..."
awk '$2 ~ /^\/var\/lib\/(kubelet|rancher)/ {print $2}' /proc/mounts | sort -r | while read -r m; do
    sudo umount -l "$m" 2>/dev/null || true
done
awk '$2 ~ /^\/data\/k3s-storage/ {print $2}' /proc/mounts | sort -r | while read -r m; do
    sudo umount -l "$m" 2>/dev/null || true
done

# 5. Clean up worker state directories and storage
echo "Cleaning up worker state directories..."
sudo rm -rf /var/lib/rancher/k3s-stream /var/lib/rancher/k3s-batch
sudo rm -rf /var/lib/kubelet-stream /var/lib/kubelet-batch
sudo rm -rf /data/k3s-storage/*

# 6. Clean up CLI binaries, kubeconfigs, and configs
sudo rm -f /usr/bin/k3s /usr/bin/kubectl
sudo rm -rf /etc/rancher /var/lib/rancher
rm -rf "$HOME/.kube"
if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
    USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
    [ -n "$USER_HOME" ] && rm -rf "$USER_HOME/.kube"
fi

echo "Teardown complete. Cluster destroyed and slate is completely clean."
