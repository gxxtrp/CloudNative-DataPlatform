#!/usr/bin/env bash
# ==============================================================================
# Cloud-Native Data Platform - Developer Toolchain Installer
# Target OS: WSL2 (AlmaLinux-10) or Bare-Metal Enterprise Linux
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

if [ "$(id -u)" -ne 0 ]; then
    log_err "This script must be run as root (or with sudo)."
    exit 1
fi

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

echo "========================================================================"
echo "  Cloud-Native Data Platform: Toolchain & Dependency Installer"
echo "========================================================================"

# ------------------------------------------------------------------------------
# 1. Base OS Packages (AlmaLinux DNF)
# ------------------------------------------------------------------------------
log_info "Installing base OS packages via dnf (make, golang, openssl, curl, tar, unzip, jq)..."
dnf install -y make golang openssl curl tar unzip jq iptables-nft >/dev/null
log_ok "Base OS packages installed."

# ------------------------------------------------------------------------------
# 2. System-wide uv (Fast Python Package Manager)
# ------------------------------------------------------------------------------
if ! command -v uv &>/dev/null; then
    log_info "Installing uv package manager..."
    curl -LsSf https://astral.sh/uv/install.sh | env CARGO_DIST_FORCE_INSTALL_DIR=/usr/local/bin sh >/dev/null 2>&1
    log_ok "uv installed at $(which uv)"
else
    log_ok "uv already installed: $(which uv)"
fi

# ------------------------------------------------------------------------------
# 3. Terraform (HashiCorp)
# ------------------------------------------------------------------------------
if ! command -v terraform &>/dev/null; then
    log_info "Installing Terraform v1.8.5..."
    curl -fsSL -o "${TMP_DIR}/terraform.zip" https://releases.hashicorp.com/terraform/1.8.5/terraform_1.8.5_linux_amd64.zip
    unzip -q -o "${TMP_DIR}/terraform.zip" -d /usr/local/bin/
    chmod +x /usr/local/bin/terraform
    log_ok "Terraform installed: $(terraform -version | head -n 1)"
else
    log_ok "Terraform already installed: $(terraform -version | head -n 1)"
fi

# ------------------------------------------------------------------------------
# 4. Helm 3
# ------------------------------------------------------------------------------
if ! command -v helm &>/dev/null; then
    log_info "Installing Helm 3..."
    curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | USE_SUDO=false HELM_INSTALL_DIR=/usr/local/bin bash >/dev/null 2>&1
    log_ok "Helm installed: $(helm version --short)"
else
    log_ok "Helm already installed: $(helm version --short)"
fi

# ------------------------------------------------------------------------------
# 5. Kustomize (Kubernetes SIGs)
# ------------------------------------------------------------------------------
if ! command -v kustomize &>/dev/null; then
    log_info "Installing Kustomize..."
    curl -s "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh" | bash -s -- /usr/local/bin >/dev/null 2>&1
    chmod +x /usr/local/bin/kustomize
    log_ok "Kustomize installed: $(kustomize version)"
else
    log_ok "Kustomize already installed: $(kustomize version)"
fi

# ------------------------------------------------------------------------------
# 6. ArgoCD CLI
# ------------------------------------------------------------------------------
if ! command -v argocd &>/dev/null; then
    log_info "Installing ArgoCD CLI..."
    curl -sSL -o /usr/local/bin/argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
    chmod +x /usr/local/bin/argocd
    log_ok "ArgoCD CLI installed: $(argocd version --client --short 2>/dev/null || echo 'installed')"
else
    log_ok "ArgoCD CLI already installed: $(which argocd)"
fi

# ------------------------------------------------------------------------------
# 7. HashiCorp Vault CLI
# ------------------------------------------------------------------------------
if ! command -v vault &>/dev/null; then
    log_info "Installing HashiCorp Vault CLI v1.18.4..."
    curl -fsSL -o "${TMP_DIR}/vault.zip" https://releases.hashicorp.com/vault/1.18.4/vault_1.18.4_linux_amd64.zip
    unzip -q -o "${TMP_DIR}/vault.zip" -d /usr/local/bin/
    chmod +x /usr/local/bin/vault
    log_ok "Vault CLI installed: $(vault version)"
else
    log_ok "Vault CLI already installed: $(vault version)"
fi

# ------------------------------------------------------------------------------
# 8. k9s (Kubernetes Terminal UI)
# ------------------------------------------------------------------------------
if ! command -v k9s &>/dev/null; then
    log_info "Installing k9s Kubernetes CLI UI..."
    curl -sSL -o "${TMP_DIR}/k9s.tar.gz" https://github.com/derailed/k9s/releases/latest/download/k9s_Linux_amd64.tar.gz
    tar -xzf "${TMP_DIR}/k9s.tar.gz" -C "${TMP_DIR}" k9s
    mv "${TMP_DIR}/k9s" /usr/local/bin/k9s
    chmod +x /usr/local/bin/k9s
    log_ok "k9s installed: $(k9s version --short 2>/dev/null || echo 'installed')"
else
    log_ok "k9s already installed: $(which k9s)"
fi

# ------------------------------------------------------------------------------
# 9. AWS CLI v2
# ------------------------------------------------------------------------------
if ! command -v aws &>/dev/null; then
    log_info "Installing AWS CLI v2..."
    curl -fsSL -o "${TMP_DIR}/awscliv2.zip" https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip
    unzip -q "${TMP_DIR}/awscliv2.zip" -d "${TMP_DIR}"
    "${TMP_DIR}/aws/install" --bin-dir /usr/local/bin --install-dir /usr/local/aws-cli --update >/dev/null
    log_ok "AWS CLI installed: $(aws --version)"
else
    log_ok "AWS CLI already installed: $(aws --version)"
fi

# ------------------------------------------------------------------------------
# 10. Verify /usr/bin Symlinks for Sudo Compatibility
# ------------------------------------------------------------------------------
for binary in k3s kubectl terraform helm kustomize argocd vault k9s uv; do
    if [ -f "/usr/local/bin/${binary}" ] && [ ! -e "/usr/bin/${binary}" ]; then
        ln -sf "/usr/local/bin/${binary}" "/usr/bin/${binary}"
    fi
done

echo ""
echo "========================================================================"
log_ok "All project tools successfully installed and verified!"
echo "========================================================================"
echo ""
printf "%-14s : %s\n" "make" "$(make --version | head -n 1)"
printf "%-14s : %s\n" "go" "$(go version)"
printf "%-14s : %s\n" "uv" "$(uv --version)"
printf "%-14s : %s\n" "terraform" "$(terraform version | head -n 1)"
printf "%-14s : %s\n" "kubectl" "$(kubectl version --client --short 2>/dev/null || kubectl version --client)"
printf "%-14s : %s\n" "helm" "$(helm version --short)"
printf "%-14s : %s\n" "kustomize" "$(kustomize version)"
printf "%-14s : %s\n" "argocd" "$(argocd version --client --short 2>/dev/null || which argocd)"
printf "%-14s : %s\n" "vault" "$(vault version)"
printf "%-14s : %s\n" "k9s" "$(k9s version --short 2>/dev/null || which k9s)"
printf "%-14s : %s\n" "aws" "$(aws --version)"
printf "%-14s : %s\n" "openssl" "$(openssl version)"
echo "========================================================================"
