SHELL := bash
.SHELLFLAGS := -euo pipefail -c

.PHONY: help test-contracts test terraform-validate terraform-plan-dataplatform terraform-plan-managed-data terraform-plan-managed-kafka terraform-plan-workload terraform-plan-workload-network terraform-plan-workload-cloud-sql terraform-plan-artifact-registry terraform-plan-cloud-run

help: ## Show available GCP Data Platform commands
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-30s %s\n", $$1, $$2}'

test-contracts: ## Run schema compatibility checks
	cd contracts && uv run python linter.py

test: ## Run the contract test suite
	cd contracts && uv run --extra dev pytest -q tests

terraform-validate: ## Validate both GCP Terraform roots without remote state
	terraform fmt -check -recursive dataplatform/terraform workload/terraform
	terraform -chdir=dataplatform/terraform/foundation init -backend=false -input=false
	terraform -chdir=dataplatform/terraform/foundation validate
	terraform -chdir=dataplatform/terraform/managed-data init -backend=false -input=false
	terraform -chdir=dataplatform/terraform/managed-data validate
	@for root in workload/terraform/foundation workload/terraform/network workload/terraform/cloud-sql workload/terraform/artifact-registry workload/terraform/cloud-run dataplatform/terraform/managed-kafka; do \
		terraform -chdir=$$root init -backend=false -input=false; \
		terraform -chdir=$$root validate; \
	done

terraform-plan-dataplatform: ## Preview Data Platform infrastructure changes
	terraform -chdir=dataplatform/terraform/foundation plan

terraform-plan-managed-data: ## Preview managed storage and BigQuery changes
	terraform -chdir=dataplatform/terraform/managed-data plan

terraform-plan-workload: ## Preview Workload infrastructure changes
	terraform -chdir=workload/terraform/foundation plan

terraform-plan-workload-network: ## Preview the private Workload VPC
	terraform -chdir=workload/terraform/network plan

terraform-plan-workload-cloud-sql: ## Preview private Cloud SQL and publisher identities
	terraform -chdir=workload/terraform/cloud-sql plan

terraform-plan-artifact-registry: ## Preview the Workload image repository
	terraform -chdir=workload/terraform/artifact-registry plan

terraform-plan-managed-kafka: ## Preview cross-project Managed Kafka and ACLs
	terraform -chdir=dataplatform/terraform/managed-kafka plan

terraform-plan-cloud-run: ## Preview private publishers; requires a populated cloud-run/terraform.tfvars
	terraform -chdir=workload/terraform/cloud-run plan
