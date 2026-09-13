#!/usr/bin/env bash
# Build and test locally; never initialize a remote backend or apply resources.
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}/../infra"
TF="${TERRAFORM_BIN:-terraform}"
actual="$("$TF" version -json | jq -r .terraform_version)"
expected="$(tr -d '\r\n' < .terraform-version)"
if [[ "$actual" != "$expected" ]]; then
  echo "Terraform $expected required; found $actual." >&2
  exit 1
fi
export TS_ENV=dev
export GOOGLE_PROJECT=sbx-workload-poc-508107
export GOOGLE_REGION=asia-southeast1
export TS_STATE_BUCKET=sbx-workload-poc-508107-tfstate
export TS_VERSION_CHECK=0
bundle check
bundle exec terraspace build foundation
stack=".terraspace-cache/${GOOGLE_REGION}/dev/stacks/foundation"
"$TF" fmt -check -recursive app
"$TF" fmt -check -recursive bootstrap
"$TF" fmt -check config/terraform/provider.tf config/terraform/versions.tf
for target in bootstrap/state "$stack" app/modules/network; do
  "$TF" "-chdir=$target" init -backend=false -input=false -lockfile=readonly
  "$TF" "-chdir=$target" validate
  "$TF" "-chdir=$target" test -no-color
done
