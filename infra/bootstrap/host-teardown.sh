#!/usr/bin/env bash
# ==============================================================================
# Cloud-Native Data Platform - 3-Node k3s Host Teardown Script
# ==============================================================================

set -euo pipefail

echo "Stopping and tearing down 3-node k3s cluster..."

sudo systemctl stop k3s-worker-stream.service || true
sudo systemctl disable k3s-worker-stream.service || true
sudo rm -f /etc/systemd/system/k3s-worker-stream.service

sudo systemctl stop k3s-worker-batch.service || true
sudo systemctl disable k3s-worker-batch.service || true
sudo rm -f /etc/systemd/system/k3s-worker-batch.service

sudo systemctl daemon-reload

if [ -f /usr/local/bin/k3s-uninstall.sh ]; then
    sudo /usr/local/bin/k3s-uninstall.sh
fi

echo "Teardown complete. Storage directory /data/k3s-storage preserved (remove manually if desired)."
