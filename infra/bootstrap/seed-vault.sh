#!/usr/bin/env bash
# ==============================================================================
# Cloud-Native Data Platform - Vault Secrets Seeding Script
# Seeds required platform and microservice runtime secrets into Vault KV v2.
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

VAULT_ADDR="${VAULT_ADDR:-http://localhost:38200}"
export VAULT_ADDR

log_info "Connecting to Vault at ${VAULT_ADDR}..."

if [ -z "${VAULT_TOKEN:-}" ]; then
    if kubectl get secret vault-unseal-keys -n vault-system &>/dev/null; then
        export VAULT_TOKEN=$(kubectl get secret vault-unseal-keys -n vault-system -o jsonpath="{.data.vault-root}" | base64 -d)
        log_ok "Retrieved root token from secret vault-unseal-keys in vault-system."
    else
        log_err "vault-unseal-keys secret not found in vault-system namespace."
        log_err "Ensure Vault is deployed and unsealed before seeding secrets (see docs/setup/README.md Step 4)."
        exit 1
    fi
fi

if ! vault status &>/dev/null; then
    log_err "Cannot connect to Vault at ${VAULT_ADDR}. Is Vault running and unsealed?"
    exit 1
fi
log_ok "Vault connectivity confirmed."

# Load custom environment secrets if present
ENV_FILE="${ENV_FILE:-.env}"
if [ -f "${ENV_FILE}" ]; then
    log_info "Loading custom runtime secrets from ${ENV_FILE}..."
    set -a
    source "${ENV_FILE}"
    set +a
elif [ -f ".env.example" ]; then
    log_info "No .env found; using defaults from .env.example..."
    set -a
    source ".env.example"
    set +a
fi

# ------------------------------------------------------------------------------
# 1. Platform Infrastructure Secrets
# ------------------------------------------------------------------------------
log_info "Seeding platform infrastructure secrets..."

vault kv put secret/platform/minio \
    access-key="${MINIO_ROOT_USER:-minioadmin}" \
    secret-key="${MINIO_ROOT_PASSWORD:-minioadmin}" \
    endpoint="${MINIO_ENDPOINT:-http://minio.platform.svc.cluster.local:9000}"

vault kv put secret/platform/postgres \
    password="${POSTGRES_PASSWORD:-postgres-super-secure-password}"

vault kv put secret/observability/grafana \
    admin-user="${GRAFANA_ADMIN_USER:-admin}" \
    admin-password="${GRAFANA_ADMIN_PASSWORD:-grafana-admin-password}"

# ------------------------------------------------------------------------------
# 2. Application Workload Secrets
# ------------------------------------------------------------------------------
log_info "Seeding application workload secrets..."

vault kv put secret/apps/order-service \
    PORT="${ORDER_SERVICE_PORT:-8080}" \
    REDPANDA_BROKERS="${ORDER_SERVICE_REDPANDA_BROKERS:-redpanda.platform.svc.cluster.local:9092}" \
    ORDERS_TOPIC="${ORDER_SERVICE_TOPIC:-orders.lifecycle}"

vault kv put secret/apps/rider-service \
    PORT="${RIDER_SERVICE_PORT:-8081}" \
    REDPANDA_BROKERS="${RIDER_SERVICE_REDPANDA_BROKERS:-redpanda.platform.svc.cluster.local:9092}" \
    RIDERS_TOPIC="${RIDER_SERVICE_TOPIC:-riders.telemetry}"

vault kv put secret/apps/stream-ingestor \
    PORT="${STREAM_INGESTOR_PORT:-8082}" \
    REDPANDA_BROKERS="${STREAM_INGESTOR_REDPANDA_BROKERS:-redpanda.platform.svc.cluster.local:9092}" \
    MINIO_ENDPOINT="${STREAM_INGESTOR_MINIO_ENDPOINT:-http://minio.platform.svc.cluster.local:9000}" \
    BRONZE_BUCKET="${STREAM_INGESTOR_BRONZE_BUCKET:-lakehouse-bronze}"

vault kv put secret/apps/traffic-generator \
    KONG_GATEWAY_URL="${TRAFFIC_GENERATOR_KONG_GATEWAY_URL:-http://kong-proxy.platform.svc.cluster.local:8000}"

echo ""
log_ok "All platform and application secrets successfully seeded into Vault KV v2!"
