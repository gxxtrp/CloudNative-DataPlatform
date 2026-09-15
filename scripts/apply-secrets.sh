#!/usr/bin/env bash
# Apply platform secrets directly to Kubernetes from the local .env file.
# This prevents committing sensitive credentials into Git.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${REPO_ROOT}/.env"

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "Error: .env file not found at ${ENV_FILE}"
  echo "Please copy .env.example to .env and configure credentials first."
  exit 1
fi

echo "Loading credentials from ${ENV_FILE}..."
# Export variables from .env ignoring comments and blank lines
set -a
# shellcheck disable=SC1090
source "${ENV_FILE}"
set +a

# Set defaults if unset
POSTGRES_USER="${POSTGRES_USER:-postgres}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:?POSTGRES_PASSWORD must be set in .env}"
POLARIS_DB_USER="${POLARIS_DB_USER:-polaris_user}"
POLARIS_DB_PASSWORD="${POLARIS_DB_PASSWORD:?POLARIS_DB_PASSWORD must be set in .env}"
POLARIS_CLIENT_ID="${POLARIS_CLIENT_ID:-polaris-root-client}"
POLARIS_CLIENT_SECRET="${POLARIS_CLIENT_SECRET:?POLARIS_CLIENT_SECRET must be set in .env}"
APICURIO_DB_USER="${APICURIO_DB_USER:-apicurio_user}"
APICURIO_DB_PASSWORD="${APICURIO_DB_PASSWORD:?APICURIO_DB_PASSWORD must be set in .env}"
GRAFANA_ADMIN_USER="${GRAFANA_ADMIN_USER:-admin}"
GRAFANA_ADMIN_PASSWORD="${GRAFANA_ADMIN_PASSWORD:?GRAFANA_ADMIN_PASSWORD must be set in .env}"

echo "Applying Kubernetes secrets..."

# 1. platform-db / postgres-credentials
echo "-> Creating secret 'postgres-credentials' in namespace 'platform-db'..."
kubectl create namespace platform-db --dry-run=client -o yaml | kubectl apply -f -
kubectl create secret generic postgres-credentials \
  --namespace platform-db \
  --from-literal=POSTGRES_USER="${POSTGRES_USER}" \
  --from-literal=POSTGRES_PASSWORD="${POSTGRES_PASSWORD}" \
  --from-literal=POSTGRES_DB="postgres" \
  --from-literal=POLARIS_PASSWORD="${POLARIS_DB_PASSWORD}" \
  --from-literal=APICURIO_PASSWORD="${APICURIO_DB_PASSWORD}" \
  --dry-run=client -o yaml | \
  kubectl annotate --local -f - "argocd.argoproj.io/compare-options=IgnoreExtraneous" -o yaml | \
  kubectl apply -f -

# 2. catalog / polaris-secrets
echo "-> Creating secret 'polaris-secrets' in namespace 'catalog'..."
kubectl create namespace catalog --dry-run=client -o yaml | kubectl apply -f -
kubectl create secret generic polaris-secrets \
  --namespace catalog \
  --from-literal=DB_USERNAME="${POLARIS_DB_USER}" \
  --from-literal=DB_PASSWORD="${POLARIS_DB_PASSWORD}" \
  --dry-run=client -o yaml | \
  kubectl annotate --local -f - "argocd.argoproj.io/compare-options=IgnoreExtraneous" -o yaml | \
  kubectl apply -f -

# 3. processing / polaris-client
echo "-> Creating secret 'polaris-client' in namespace 'processing'..."
kubectl create namespace processing --dry-run=client -o yaml | kubectl apply -f -
kubectl create secret generic polaris-client \
  --namespace processing \
  --from-literal=credential="${POLARIS_CLIENT_ID}:${POLARIS_CLIENT_SECRET}" \
  --dry-run=client -o yaml | \
  kubectl annotate --local -f - "argocd.argoproj.io/compare-options=IgnoreExtraneous" -o yaml | \
  kubectl apply -f -

# 4. schema-registry / apicurio-secrets
echo "-> Creating secret 'apicurio-secrets' in namespace 'schema-registry'..."
kubectl create namespace schema-registry --dry-run=client -o yaml | kubectl apply -f -
kubectl create secret generic apicurio-secrets \
  --namespace schema-registry \
  --from-literal=DB_USERNAME="${APICURIO_DB_USER}" \
  --from-literal=DB_PASSWORD="${APICURIO_DB_PASSWORD}" \
  --dry-run=client -o yaml | \
  kubectl annotate --local -f - "argocd.argoproj.io/compare-options=IgnoreExtraneous" -o yaml | \
  kubectl apply -f -

# 5. observability / grafana-admin-credentials
echo "-> Creating secret 'grafana-admin-credentials' in namespace 'observability'..."
kubectl create namespace observability --dry-run=client -o yaml | kubectl apply -f -
kubectl create secret generic grafana-admin-credentials \
  --namespace observability \
  --from-literal=admin-user="${GRAFANA_ADMIN_USER}" \
  --from-literal=admin-password="${GRAFANA_ADMIN_PASSWORD}" \
  --dry-run=client -o yaml | \
  kubectl annotate --local -f - "argocd.argoproj.io/compare-options=IgnoreExtraneous" -o yaml | \
  kubectl apply -f -

echo "All platform secrets applied successfully to cluster from .env."
