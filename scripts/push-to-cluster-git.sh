#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

echo "Starting port-forward to git-server in platform namespace..."
kubectl port-forward svc/git-server -n platform 9418:9418 >/dev/null 2>&1 &
PF_PID=$!

cleanup() {
  kill "${PF_PID}" 2>/dev/null || true
}
trap cleanup EXIT

sleep 2

cd "${REPO_ROOT}"
echo "Pushing codex/refac and main to git://127.0.0.1:9418/repo.git..."
git push git://127.0.0.1:9418/repo.git HEAD:refs/heads/codex/refac
git push git://127.0.0.1:9418/repo.git HEAD:refs/heads/main

echo "Git push to in-cluster git server completed successfully."
