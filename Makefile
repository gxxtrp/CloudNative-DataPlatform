# ==============================================================================
# Cloud-Native Data Platform - Domain-Driven Makefile
# ==============================================================================

SHELL := bash
.SHELLFLAGS := -euo pipefail -c

WSL_DISTRO := AlmaLinux-10

.PHONY: help host-bootstrap host-teardown infra-init infra-plan infra-apply infra-destroy \
        test-contracts test-streaming test-dlq test-compaction run-batch verify dashboard test

help: ## Show this help message
	@echo "Cloud-Native Data Platform"
	@echo "Available commands:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

# ------------------------------------------------------------------------------
# Domain: Platform Infrastructure & Host Bootstrap (infra/)
# ------------------------------------------------------------------------------

host-bootstrap: ## Bootstrap native 3-node k3s cluster in WSL2 (AlmaLinux-10)
	@echo "[+] Starting 3-node k3s bootstrap in WSL2..."
	wsl -d $(WSL_DISTRO) -e bash infra/bootstrap/host-bootstrap.sh

host-teardown: ## Teardown 3-node k3s cluster in WSL2
	@echo "[+] Tearing down 3-node k3s cluster in WSL2..."
	wsl -d $(WSL_DISTRO) -e bash infra/bootstrap/host-teardown.sh

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
	@echo "[+] Verifying 3-node cluster and platform health..."
	wsl -d $(WSL_DISTRO) -e bash -c "kubectl get nodes -o wide && kubectl get pods -A"

dashboard: ## Display all active Web UI endpoints
	@echo "========================================================================"
	@echo "  Cloud-Native Data Platform - Operational Endpoints"
	@echo "========================================================================"
	@echo "  Kong API Gateway:     http://localhost:30000/api/v1"
	@echo "  ArgoCD GitOps UI:     http://localhost:30080"
	@echo "  Argo Workflows UI:    http://localhost:32746"
	@echo "  Longhorn Storage UI:  http://localhost:30088"
	@echo "  Apache Flink Web UI:  http://localhost:38081"
	@echo "  Grafana SRE Monitor:  http://localhost:30300"
	@echo "  Jaeger Tracing UI:    http://localhost:31686"
	@echo "  Prometheus TSDB:      http://localhost:9090"
	@echo "  Alertmanager UI:      http://localhost:9093"
	@echo "  Vault Secrets UI:     http://localhost:38200"
	@echo "========================================================================"

