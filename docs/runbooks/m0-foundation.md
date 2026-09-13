# Start the Terraspace foundation

Use this runbook to validate and prepare the first M0 infrastructure slice.
It targets project `sbx-workload-poc-508107` in Singapore (`asia-southeast1`).
The cluster, storage grants and GitOps acceptance workload are tracked in
[the remaining M0 tickets](../../.scratch/m0-foundation/spec.md).

## Validate locally

Use a Linux shell with Ruby **3.3**, Bundler **2.5.22**, Git, jq and Terraform
**1.15.8** installed. Native gem compilation also needs a C/C++ toolchain, Make
and Ruby development headers. The Gemfile and lockfile pin Terraspace 2.2.20
and its Google plugin 0.5.0; the provider is pinned to 7.40.0 with Linux and
Windows checksums. Install the Ruby dependencies from the repository root:

```bash
cd infra
bundle config set --local path vendor/bundle
bundle install
cd ..
```

From the repository root, run:

```bash
bash scripts/check-foundation.sh
```

The script builds Terraspace, initializes providers with the remote backend
disabled, validates Terraform and runs five mock-provider checks. It never
creates GCP resources. Provider installation requires network access.
`TERRAFORM_BIN` can select an alternate Terraform executable for this script.

Terraspace 2.2.20 rejects Terraform newer than 1.5.7 by default. This workflow
sets `TS_VERSION_CHECK=0`, the
[documented override](https://terraspace.cloud/docs/terraform/license/).
The Terraform version constraint still enforces 1.15.8.

## Review deployment inputs

Complete [the deployment review](../../.scratch/m0-foundation/issues/02-deployment-review.md).
The proposed CIDRs are not automatically checked against your LAN, VPN or GCP
inventory. Mock tests do not demonstrate live connectivity or IAM denial.

The `foundation` stack refuses a plan until `deployment_reviewed` is true.
State bootstrap is a separate explicit operation and must follow the same review.

## Bootstrap state

The operator needs Application Default Credentials and permission to create a
Cloud Storage bucket in the existing billed project. Foundation additionally
needs project service enablement, network administration, service-account creation
and project IAM policy update permissions. Use a dedicated operator identity;
do not grant these permissions to GKE nodes or workload identities.

In a Bash shell, from the repository root, load the dev settings:

```bash
source infra/dev.env.example
```

Review the proposed globally unique `TS_STATE_BUCKET` name before creating it.
With reviewed inputs, initialize and inspect the explicit bootstrap plan:

```bash
terraform -chdir=infra/bootstrap/state init
terraform -chdir=infra/bootstrap/state plan \
  -var="project_id=$GOOGLE_PROJECT" \
  -var="location=$GOOGLE_REGION" \
  -var="bucket_name=$TS_STATE_BUCKET" \
  -out=state.tfplan
```

Apply the reviewed plan when provisioning is authorized:

```bash
terraform -chdir=infra/bootstrap/state apply state.tfplan
```

Bootstrap owns only the backend bucket. Its state remains local under
`infra/bootstrap/state/`; preserve an access-controlled backup before switching
machines. Do not commit state or saved plans. Bucket versioning, public access
prevention, uniform access and Terraform deletion protection are enabled.
Terraspace backend auto-creation is disabled, so a plan cannot implicitly create
the bucket. Do not destroy/recreate state storage during ordinary idle periods.

## Plan the foundation

After recording the deployment review, run from `infra/`:

```bash
export TF_VAR_deployment_reviewed=true
bundle exec terraspace plan foundation
```

Review the real plan before applying. The backend prefix is
`sbx-workload-poc-508107/asia-southeast1/dev/foundation`, following
[Terraspace GCS backend expansion](https://terraspace.cloud/docs/config/backend/examples/gcs/).
The stack owns project API enablement, a custom VPC, one subnet with Pod/Service
ranges, Private Google Access, subnet-scoped NAT, and the node identity.
NAT permits outbound connectivity; it does not enforce a destination allowlist.

The plain Terraform network module is independent of Terraspace. Subsequent
stacks consume its outputs using
[Terraspace dependency references](https://terraspace.cloud/docs/dependencies/tfvars/).
Application workloads and Kubernetes policies belong to GitOps, outside these modules.

## Evidence and limits

Local mock tests cover private/versioned state, explicit subnet/NAT configuration,
node IAM scope, malformed IPv4 input, and the deployment-review guard.
No cloud resources, cluster, Argo reconciliation, live access checks or billing
measurements have been produced by this first slice. M0 remains in progress.
