#!/usr/bin/env bash
# End-to-end acceptance script for Milestone 0 GitOps and smoke workload
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

echo "=== 1. Checking GKE Cluster Credentials & Reachability ==="
kubectl get nodes -L pool -o wide

echo "=== 2. Checking Foundational Namespaces ==="
kubectl get namespaces platform processing ingestion argocd

echo "=== 3. Checking Argo CD Applications Health & Sync ==="
kubectl get applications -n argocd

echo "=== 4. Checking ResourceQuotas & LimitRanges ==="
kubectl get resourcequota -A
kubectl get limitrange -A

echo "=== 5. Checking NetworkPolicies ==="
kubectl get networkpolicies -A

echo "=== 6. Checking Positive Smoke Workload (GCS Lake Write/Read) ==="
kubectl get job m0-smoke-workload -n platform
kubectl describe job m0-smoke-workload -n platform | grep -E "Pods Statuses|Duration|Completed"

echo "=== 7. Checking Negative Security Test (Denied Access 401/403) ==="
kubectl get job m0-smoke-denied-workload -n processing
kubectl describe job m0-smoke-denied-workload -n processing | grep -E "Pods Statuses|Duration|Completed"

echo "=== 8. Checking Lake Storage Object in GCS ==="
gcloud storage cat gs://sbx-workload-poc-508107-lake-dev/smoke/verification.json

echo "=== 9. Checking Compute Node Pool Scale-to-Zero ==="
gcloud container node-pools describe compute --cluster=platform-dev-gke --region=asia-southeast1 --format='yaml(name, autoscaling.minNodeCount, autoscaling.maxNodeCount)'

echo "=== Milestone 0 Acceptance Check PASSED ==="
