#!/usr/bin/env bash
set -euo pipefail

# Setup bridge k3s-br0
if ! ip link show k3s-br0 &>/dev/null; then
    ip link add name k3s-br0 type bridge
    ip addr add 10.200.0.1/24 dev k3s-br0
    ip link set k3s-br0 up
fi

# Configure iptables forwarding & NAT masquerade
iptables -C FORWARD -i k3s-br0 -j ACCEPT 2>/dev/null || iptables -A FORWARD -i k3s-br0 -j ACCEPT
iptables -C FORWARD -o k3s-br0 -j ACCEPT 2>/dev/null || iptables -A FORWARD -o k3s-br0 -j ACCEPT
iptables -t nat -C POSTROUTING -s 10.200.0.0/24 ! -o k3s-br0 -j MASQUERADE 2>/dev/null || \
    iptables -t nat -A POSTROUTING -s 10.200.0.0/24 ! -o k3s-br0 -j MASQUERADE

setup_worker_netns() {
    local NS_NAME="$1"
    local VETH_HOST="$2"
    local VETH_NS="$3"
    local NODE_IP="$4"

    if ! ip netns list | grep -qw "$NS_NAME"; then
        ip netns add "$NS_NAME"
    fi
    ip netns exec "$NS_NAME" ip link set lo up

    if ! ip link show "$VETH_HOST" &>/dev/null; then
        ip link add "$VETH_HOST" type veth peer name "$VETH_NS"
        ip link set "$VETH_HOST" master k3s-br0
        ip link set "$VETH_HOST" up
        ip link set "$VETH_NS" netns "$NS_NAME"
        ip netns exec "$NS_NAME" ip link set "$VETH_NS" name eth0
        ip netns exec "$NS_NAME" ip addr add "$NODE_IP/24" dev eth0
        ip netns exec "$NS_NAME" ip link set eth0 up
        ip netns exec "$NS_NAME" ip route replace default via 10.200.0.1
    fi
}

setup_worker_netns ns-worker-stream veth-st-host veth-st-ns 10.200.0.2
setup_worker_netns ns-worker-batch veth-bt-host veth-bt-ns 10.200.0.3

echo "Worker network namespaces and bridge initialized successfully."
