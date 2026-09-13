# Set up platform tools on Red Hat-based Linux

This guide is for the platform builder preparing a Red Hat-based Linux host for
the foundation milestone. It installs the required system packages and the
project-local Terraspace bundle. It does not authenticate to Google Cloud or
create cloud resources.

## Tools installed now

The installation script installs these foundation tools:

| Tool | Installation source | Use |
|---|---|---|
| Git, Ruby, Bundler, and jq | Red Hat package repositories | Store configuration, run Terraspace, and inspect JSON output. |
| Terraform | HashiCorp RPM repository | Define and plan GCP resources. |
| Google Cloud CLI, GKE plugin, and kubectl | Google Cloud RPM repository | Authenticate to GCP and inspect GKE. |
| Helm | Verified Helm release archive | Bootstrap Argo CD and validate charts. |
| Terraspace and the Google plugin | Project-local Ruby bundle | Compose reusable Terraform modules into GCP stacks. |

The setup excludes the Argo Workflows CLI, dbt, Python, and data-engine tools.
Add them with the milestones that use them. A container engine is also outside
this setup because it needs host-level, distribution-specific configuration; CI
can build the M0 test image.

## Before you begin

Use Enterprise Linux 8, 9, or 10: Red Hat Enterprise Linux, Rocky Linux,
AlmaLinux, or CentOS. You need `sudo` access and Internet access to the Red
Hat, HashiCorp, Google Cloud, Helm, and RubyGems package sources.

The script adds HashiCorp and Google Cloud RPM repositories, then verifies the
pinned Helm archive's SHA-256 checksum before it installs Helm. Read the source
definitions in [the setup script](../../scripts/setup-platform-tools.sh) before
you run it. Google documents the Cloud CLI RPM packages and the separate GKE
authentication plugin in its [Linux installation guide](https://docs.cloud.google.com/sdk/docs/install-sdk).

## Install and verify

Run the script from the repository root:

```bash
bash scripts/setup-platform-tools.sh
```

The script installs system packages through `sudo dnf`, configures the required
RPM repositories, installs Terraspace in your Linux user cache, and verifies
each command. It does not open a browser, change the selected GCP project, or
provision GCP. Keeping native Ruby gems outside a WSL-mounted Windows repository
avoids Bundler's unsafe world-writable-directory check.

After the script completes, commit `infra/Gemfile.lock`. It pins the complete
Terraspace dependency set that Bundler resolved.

## Authenticate after setup

After the network design, project selection, and bootstrap identity are settled,
authenticate with the Google Cloud CLI:

```bash
gcloud auth login
gcloud auth list
```

Select the project only after its identifier is confirmed:

```bash
gcloud config set project PROJECT_ID
```

Replace `PROJECT_ID` with the approved GCP project ID. Do not run Terraspace
plans or applies until the M0 network, region, and node bounds are settled.

## Use Terraspace

Run Terraspace through Bundler from the `infra` directory:

```bash
bundle exec terraspace version
```

The infrastructure stack and backend configuration are introduced in M0.
