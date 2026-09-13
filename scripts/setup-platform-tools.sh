#!/usr/bin/env bash
# Installs and verifies foundation tools on Red Hat-based Linux.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPOSITORY_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

if [[ ! -r /etc/os-release ]]; then
  echo "This script requires a Red Hat-based Linux host." >&2
  exit 1
fi

source /etc/os-release
case "${ID}" in
  rhel|rocky|almalinux|centos) ;;
  *)
    echo "Unsupported distribution: ${ID}. Use a Red Hat-based host." >&2
    exit 1
    ;;
esac

EL_MAJOR=$((10#${VERSION_ID%%.*}))
if (( EL_MAJOR < 8 || EL_MAJOR > 10 )); then
  echo "Unsupported Enterprise Linux version: ${VERSION_ID}." >&2
  exit 1
fi
if [[ "${EL_MAJOR}" == "10" ]]; then
  GOOGLE_EL="el10"
  GOOGLE_GPG_KEY="https://packages.cloud.google.com/yum/doc/rpm-package-key-v10.gpg"
else
  GOOGLE_EL="el9"
  GOOGLE_GPG_KEY="https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg"
fi

case "$(uname -m)" in
  x86_64|aarch64) GOOGLE_ARCH="$(uname -m)" ;;
  *)
    echo "Unsupported architecture: $(uname -m)." >&2
    exit 1
    ;;
esac

sudo dnf install -y ca-certificates curl dnf-plugins-core gcc git jq make \
  ruby ruby-devel rubygem-bundler tar

sudo dnf config-manager --add-repo \
  https://rpm.releases.hashicorp.com/RHEL/hashicorp.repo

sudo tee /etc/yum.repos.d/google-cloud-sdk.repo >/dev/null <<REPOSITORY
[google-cloud-cli]
name=Google Cloud CLI
baseurl=https://packages.cloud.google.com/yum/repos/cloud-sdk-${GOOGLE_EL}-${GOOGLE_ARCH}
enabled=1
gpgcheck=1
repo_gpgcheck=0
gpgkey=${GOOGLE_GPG_KEY}
REPOSITORY

sudo dnf install -y google-cloud-cli \
  google-cloud-cli-gke-gcloud-auth-plugin kubectl terraform

HELM_VERSION="v3.22.0"
case "${GOOGLE_ARCH}" in
  x86_64) HELM_ARCH="amd64" ;;
  aarch64) HELM_ARCH="arm64" ;;
esac
HELM_ARCHIVE="helm-${HELM_VERSION}-linux-${HELM_ARCH}.tar.gz"
HELM_DIRECTORY="$(mktemp -d)"
trap 'rm -rf "${HELM_DIRECTORY}"' EXIT

curl --fail --location --silent --show-error \
  --output "${HELM_DIRECTORY}/${HELM_ARCHIVE}" \
  "https://get.helm.sh/${HELM_ARCHIVE}"
curl --fail --location --silent --show-error \
  --output "${HELM_DIRECTORY}/${HELM_ARCHIVE}.sha256" \
  "https://get.helm.sh/${HELM_ARCHIVE}.sha256"
HELM_ACTUAL_SHA256="$(sha256sum "${HELM_DIRECTORY}/${HELM_ARCHIVE}" | awk '{print $1}')"
HELM_EXPECTED_SHA256="$(cat "${HELM_DIRECTORY}/${HELM_ARCHIVE}.sha256")"
if [[ "${HELM_ACTUAL_SHA256}" != "${HELM_EXPECTED_SHA256}" ]]; then
  echo "Helm archive checksum verification failed." >&2
  exit 1
fi
tar --extract --gzip --file "${HELM_DIRECTORY}/${HELM_ARCHIVE}" \
  --directory "${HELM_DIRECTORY}"
sudo install --mode=0755 "${HELM_DIRECTORY}/linux-${HELM_ARCH}/helm" \
  /usr/local/bin/helm

cd "${REPOSITORY_ROOT}/infra"
BUNDLE_DIRECTORY="${XDG_CACHE_HOME:-${HOME}/.cache}/data-platfrom/bundle"
mkdir -p "${BUNDLE_DIRECTORY}"
bundle config set --local path "${BUNDLE_DIRECTORY}"
bundle install

git --version
terraform version
gcloud version
gke-gcloud-auth-plugin --version
kubectl version --client=true --output=yaml
helm version --short
jq --version
bundle exec terraspace version

cat <<'MESSAGE'

Tool installation and verification completed.

Next, authenticate interactively with `gcloud auth login`, select the intended
GCP project, and configure Terraform only after the network and sizing choices
are recorded. This script does not create, modify, or authenticate to GCP.
MESSAGE
