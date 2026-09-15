#!/usr/bin/env bash
# Build and publish the public-batch-ingest container image to GCP Artifact Registry
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

PROJECT_ID="sbx-workload-poc-508107"
REGION="asia-southeast1"
REPO="platform-dev-images"
IMAGE_TAG="${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPO}/public-batch-ingest:latest"

echo "=== Building and pushing Public Batch Ingest container image ==="
echo "Target Image: ${IMAGE_TAG}"
echo "Context Dir: ${REPO_ROOT}/workloads/ingestion/public-batch"

gcloud builds submit "${REPO_ROOT}/workloads/ingestion/public-batch" \
  --tag "${IMAGE_TAG}" \
  --project "${PROJECT_ID}"

echo "=== Image build and push completed successfully ==="
