#!/usr/bin/env bash
# ==============================================================================
# Cloud-Native Data Platform - k3s Host Teardown Script
# ==============================================================================

set -euo pipefail

# Ensure terminal settings (echo, carriage return) are always restored
_restore_tty() {
    stty sane 2>/dev/null || stty echo icanon onlcr 2>/dev/null || true
}
trap _restore_tty EXIT INT TERM

echo "Stopping and tearing down k3s cluster..."

# 1. Stop and disable all k3s services (server, agents, helpers)
echo "Stopping all k3s systemd services..."
sudo systemctl stop 'k3s*.service' 2>/dev/null || true
sudo systemctl disable 'k3s*.service' 2>/dev/null || true
sudo rm -f /etc/systemd/system/k3s*.service
sudo systemctl daemon-reload

# 2. Terminate leftover k3s and container processes safely
# NOTE: Never use 'pkill -f <name>' here because '-f' matches the full cmdline of
# 'sudo pkill -f <name>', causing pkill to send SIGKILL to itself and sudo!
# When sudo is SIGKILLed, it cannot restore tty settings, leaving terminal echo disabled.
echo "Terminating leftover k3s and container processes..."
for proc in containerd-shim containerd-shim-runc-v2 k3s; do
    sudo killall -9 "$proc" 2>/dev/null || true
    sudo pkill -9 -x "$proc" 2>/dev/null || true
done

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
if id "x" &>/dev/null; then
    X_HOME=$(getent passwd "x" | cut -d: -f6)
    [ -n "$X_HOME" ] && rm -rf "$X_HOME/.kube"
fi

_restore_tty
echo "Teardown complete. Cluster destroyed and slate is completely clean."
