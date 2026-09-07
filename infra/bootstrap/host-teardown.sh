#!/usr/bin/env bash
# ==============================================================================
# Cloud-Native Data Platform - 3-Node k3s Host Teardown Script
# ==============================================================================

set -euo pipefail

echo "Stopping and tearing down 3-node k3s cluster..."

# 1. Stop and disable all k3s services (server, agents, helpers)
echo "Stopping all k3s systemd services..."
for svc in k3s.service k3s-agent.service k3s-worker-stream.service k3s-worker-batch.service k3s-worker-netns.service k3s-nodeport-relay.service; do
    sudo systemctl stop "$svc" 2>/dev/null || true
    sudo systemctl disable "$svc" 2>/dev/null || true
    sudo rm -f "/etc/systemd/system/$svc"
done
sudo systemctl daemon-reload

# 2. Terminate any leftover containerd-shim, containerd, or k3s processes
echo "Terminating leftover k3s and container processes..."
sudo pkill -9 -f containerd-shim 2>/dev/null || true
sudo pkill -9 -f "k3s server" 2>/dev/null || true
sudo pkill -9 -f "k3s agent" 2>/dev/null || true

# 3. Clean up worker network namespaces and virtual bridge
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

# 4. Uninstall k3s server (if uninstaller exists)
if [ -f /usr/local/bin/k3s-uninstall.sh ]; then
    echo "Uninstalling k3s server..."
    sudo /usr/local/bin/k3s-uninstall.sh || true
fi

# 5. Unmount any remaining container, runtime, and kubelet mounts
echo "Unmounting leftover container, runtime, and kubelet mounts..."
awk '$2 ~ /^\/(run\/k3s|var\/lib\/(kubelet|rancher)|data\/k3s-storage)/ {print $2}' /proc/mounts | sort -r | while read -r m; do
    sudo umount -l "$m" 2>/dev/null || true
done

# 6. Clean up worker state directories, runtimes, and storage
echo "Cleaning up state directories and storage..."
sudo rm -rf /run/k3s
sudo rm -rf /var/lib/rancher/k3s-stream /var/lib/rancher/k3s-batch
sudo rm -rf /var/lib/kubelet-stream /var/lib/kubelet-batch
sudo rm -rf /data/k3s-storage/*

# 7. Clean up CLI binaries, kubeconfigs, and configs
sudo rm -f /usr/bin/k3s /usr/bin/kubectl
sudo rm -rf /etc/rancher /var/lib/rancher
rm -rf "$HOME/.kube"
if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
    USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
    [ -n "$USER_HOME" ] && rm -rf "$USER_HOME/.kube"
fi

echo "Teardown complete. Cluster destroyed and slate is completely clean."
