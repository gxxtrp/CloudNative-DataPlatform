# ==============================================================================
# Cloud-Native Data Platform - Domain-Driven Makefile
# ==============================================================================

SHELL := bash
.SHELLFLAGS := -euo pipefail -c

WSL_DISTRO := AlmaLinux-10
export UV_LINK_MODE ?= copy

# Detect if executing inside WSL or native Linux environment
IS_INSIDE_WSL := $(shell if [ -f /proc/version ] && grep -qi microsoft /proc/version 2>/dev/null; then echo 1; else echo 0; fi)

ifeq ($(IS_INSIDE_WSL),1)
RUN_WSL :=
RUN_WSL_ROOT := sudo
else
RUN_WSL := wsl -d $(WSL_DISTRO) -e
RUN_WSL_ROOT := wsl -d $(WSL_DISTRO) -u root -e
endif

.PHONY: help install-tools host-bootstrap host-bootstrap-single host-teardown infra-init infra-plan infra-apply infra-destroy seed-secrets \
        test-contracts test-streaming test-dlq test-compaction run-batch verify dashboard test

help: ## Show this help message
	@echo "Cloud-Native Data Platform"
	@echo "Available commands:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

# ------------------------------------------------------------------------------
# Domain: Platform Infrastructure & Host Bootstrap (infra/)
# ------------------------------------------------------------------------------

install-tools: ## Install all required developer tools, runtimes, and drivers in WSL
	@echo "[+] Installing developer tools, CLIs, and drivers in WSL..."
	$(RUN_WSL_ROOT) bash infra/bootstrap/install-tools.sh

create: host-bootstrap ## Alias for host-bootstrap

host-bootstrap: ## Bootstrap single-node k3s cluster in WSL2 (AlmaLinux-10)
	@echo "[+] Starting single-node k3s bootstrap in WSL2..."
	$(RUN_WSL) bash infra/bootstrap/host-bootstrap-single.sh

host-teardown: ## Teardown k3s cluster in WSL2
	@echo "[+] Tearing down k3s cluster in WSL2..."
	$(RUN_WSL) bash infra/bootstrap/host-teardown.sh

infra-init: ## Initialize Terraform for self_manage environment
	@echo "[+] Initializing Terraform (self_manage)..."
	cd infra/terraform/envs/self_manage && terraform init

infra-plan: ## Run Terraform Plan for self_manage environment
	@echo "[+] Running Terraform Plan (self_manage)..."
	cd infra/terraform/envs/self_manage && terraform fmt -check && terraform validate && terraform plan

infra-apply: ## Apply Terraform Infrastructure for self_manage environment
	@echo "[+] Applying Terraform Infrastructure (self_manage)..."
	cd infra/terraform/envs/self_manage && terraform apply -auto-approve

infra-destroy: ## Destroy Terraform Infrastructure (self_manage)
	@echo "[+] Destroying Terraform Infrastructure (self_manage)..."
	cd infra/terraform/envs/self_manage && terraform destroy -auto-approve

seed-secrets: ## Seed platform and application runtime secrets into Vault KV v2
	@echo "[+] Seeding runtime secrets into HashiCorp Vault..."
	$(RUN_WSL) bash infra/bootstrap/seed-vault.sh

infra-plan-aws: ## Run Terraform Plan for free_tier_aws environment
	@echo "[+] Running Terraform Plan (free_tier_aws)..."
	cd infra/terraform/envs/free_tier_aws && terraform fmt -check && terraform validate && terraform plan

# ------------------------------------------------------------------------------
# Domain: Data Contracts (contracts/)
# ------------------------------------------------------------------------------

test-contracts: ## Run Data Contract Schema backward-compatibility linter
	@echo "[+] Running Data Contract compatibility linter..."
	cd contracts && uv run python linter.py

# ------------------------------------------------------------------------------
# Domain: Data Platform Operational Engines (contracts/tools/)
# ------------------------------------------------------------------------------

test-compaction: ## Run autonomous Lakehouse Parquet compactor engine test
	@echo "[+] Running Lakehouse Compactor test..."
	cd contracts && uv run pytest tests/test_platform_engines.py -k test_compactor -v

run-batch: ## Run daily batch financial settlement engine test
	@echo "[+] Running Financial Settlement Engine test..."
	cd contracts && uv run pytest tests/test_platform_engines.py -k test_settlement -v

test-dlq: ## Run DLQ incident triage and safe replay engine test
	@echo "[+] Running DLQ Incident Triage test..."
	cd contracts && uv run pytest tests/test_platform_engines.py -k test_dlq -v

test-streaming: ## Run streaming lakehouse ingestor test
	@echo "[+] Running Streaming Lakehouse Ingestor test..."
	cd contracts && uv run pytest tests/test_platform_engines.py -k test_stream_ingestor -v

# ------------------------------------------------------------------------------
# Domain: Autonomous Go Microservices (apps/)
# ------------------------------------------------------------------------------

build-apps: ## Compile all 5 autonomous Go microservices
	@echo "[+] Compiling Go microservices..."
	cd apps/order-service && go build -o /dev/null main.go
	cd apps/rider-service && go build -o /dev/null main.go
	cd apps/stream-ingestor && go build -o /dev/null main.go
	cd apps/settlement-engine && go build -o /dev/null main.go
	cd apps/traffic-generator && go build -o /dev/null main.go
	@echo "[+] All Go microservices compiled successfully."

docker-build: ## Build Docker images for all 5 Go microservices
	@echo "[+] Building Docker images for Go microservices..."
	docker build -t platform/order-service:latest apps/order-service
	docker build -t platform/rider-service:latest apps/rider-service
	docker build -t platform/stream-ingestor:latest apps/stream-ingestor
	docker build -t platform/settlement-engine:latest apps/settlement-engine
	docker build -t platform/traffic-generator:latest apps/traffic-generator

test: ## Run complete automated test suite
	@echo "[+] Running contract compatibility linter..."
	cd contracts && uv run python linter.py
	@echo "[+] Running pytest suite..."
	cd contracts && uv run --extra dev pytest -v tests

# ------------------------------------------------------------------------------
# Verification & Observability
# ------------------------------------------------------------------------------

verify: ## Run comprehensive end-to-end verification smoke test
	@echo "[+] Verifying single-node cluster and platform health..."
	$(RUN_WSL) bash -c "kubectl get nodes -o wide && kubectl get pods -A"

dashboard: ## Display all active Web UI endpoints
	@echo "========================================================================"
	@echo "  Cloud-Native Data Platform - Operational Endpoints"
	@echo "========================================================================"
	@echo "  Kong API Gateway:     http://localhost:30000/api/v1"
	@echo "  ArgoCD GitOps UI:     https://localhost:30443 (HTTP: 30080)"
	@echo "  Argo Workflows UI:    http://localhost:32746"
	@echo "  Apache Flink Web UI:  http://localhost:38081"
	@echo "  Grafana SRE Monitor:  http://localhost:30300"
	@echo "  Prometheus TSDB:      http://localhost:9090"
	@echo "  Alertmanager UI:      http://localhost:9093"
	@echo "  Vault Secrets UI:     http://localhost:38200"
	@echo "  [DEFERRED] Jaeger:    not deployed (single-node, memory constraints)"
	@echo "  [DEFERRED] Loki:      not deployed (single-node, memory constraints)"
	@echo "========================================================================"

