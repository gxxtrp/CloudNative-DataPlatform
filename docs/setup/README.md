# Cloud-Native Data Platform: End-to-End Setup & Operations Guide

**Domain**: Platform Infrastructure, Engineering Operations & Developer Experience (`docs/setup/`)  
**Scope**: Complete From-Scratch Provisioning, Toolchain Automation, Single-Node k3s Cluster in WSL2, Terraform Substrate, HashiCorp Vault Secrets, and GitOps ArgoCD Synchronization.

---

## 📋 Table of Contents

1. [Architecture & System Prerequisites](#1-architecture--system-prerequisites)
2. [Step 1: Automated Toolchain & Dependency Installation](#2-step-1-automated-toolchain--dependency-installation)
3. [Step 2: Single-Node k3s Cluster Bootstrap](#3-step-2-single-node-k3s-cluster-bootstrap)
4. [Step 3: Platform Substrate Provisioning (Terraform IaC)](#4-step-3-platform-substrate-provisioning-terraform-iac)
5. [Step 4: Deploy HashiCorp Vault & Security Operators](#5-step-4-deploy-hashicorp-vault--security-operators)
6. [Step 5: Seed Platform Runtime Secrets into Vault](#6-step-5-seed-platform-runtime-secrets-into-vault)
7. [Step 6: Autonomous Microservices Compilation & Contract Linting](#7-step-6-autonomous-microservices-compilation--contract-linting)
8. [Step 7: GitOps Application Bootstrap (ArgoCD App-of-Apps)](#8-step-7-gitops-application-bootstrap-argocd-app-of-apps)
9. [Step 8: Verification, Testing & Operational Web UIs](#9-step-8-verification-testing--operational-web-uis)
10. [Step 9: Clean Cluster Teardown & Reset](#10-step-9-clean-cluster-teardown--reset)
11. [Troubleshooting & SRE Runbooks](#11-troubleshooting--sre-runbooks)

---

## 1. Architecture & System Prerequisites

The platform executes entirely within a resource-optimized, single-node Kubernetes cluster hosted inside **WSL2 (AlmaLinux-10)** on Windows, providing 100% production fidelity with strict zero Docker-in-Docker overhead, a **$0.00 cloud cost guarantee**, and a lightweight **~1.1 GiB baseline RAM footprint**.

```mermaid
flowchart TD
    subgraph WindowsHost["Windows 10/11 Host"]
        subgraph WSL["WSL2: AlmaLinux-10 (systemd enabled)"]
            subgraph Node["Unified Node: k3s-node (control-plane + streaming + batch)"]
                K8S[k3s API Server :6443]
                ARGO[ArgoCD Core :30080 / :30443]
                WF[Argo Workflows :32746]
                KONG[Kong API Gateway :30000]
                RP[Redpanda Kafka Broker]
                FLINK[Apache Flink :38081]
                MINIO[MinIO Lakehouse S3 :9000]
                VAULT[HashiCorp Vault :38200]
                PROM[Prometheus :9090]
                GRAF[Grafana :30300]
                APPS[Autonomous Microservices]
            end

            STORAGE[(Host Mount: /data/k3s-storage<br/>k3s local-path-provisioner)]
            Node -.->|Direct Host Volume Mounts| STORAGE
        end
    end
```

### Hardware & Environment Requirements
- **Host OS**: Windows 10/11 with WSL2 enabled.
- **WSL Distro**: AlmaLinux-10 (Enterprise Linux 10-compatible).
- **WSL Systemd**: Enabled in `/etc/wsl.conf`:
  ```ini
  [boot]
  systemd=true
  ```
- **Compute Resources**: Minimum 4 CPU cores, 8 GB RAM, 20 GB free disk space.
- **Host Storage**: Dedicated directory `/data/k3s-storage` configured for `local-path` provisioner volumes to prevent Windows drive churn.

---

## 2. Step 1: Automated Toolchain & Dependency Installation

The repository provides an automated, idempotent setup script that installs all required developer CLIs, runtimes, and Linux storage daemons.

### Run the Installer

> [!TIP]
> **Terminal Environment:** All `make` targets and workflows are designed to be executed **inside an active WSL terminal** (`wsl` in PowerShell). All developer tools (`make`, `terraform`, `kubectl`, `helm`, `uv`, `go`) run natively inside AlmaLinux-10.

From the WSL terminal, execute:

```bash
make install-tools
```

*Or execute directly in WSL with root privileges:*
```bash
sudo bash infra/bootstrap/install-tools.sh
```

### Installed Tool Matrix

| Tool | Category | Installed Version | Role in Platform |
| :--- | :--- | :--- | :--- |
| **GNU Make** | Automation | `4.4.1` | Orchestrates repository build, test, and deploy targets. |
| **Go Runtime** | Language | `1.26.7` | Compiles the 5 autonomous microservices in `apps/`. |
| **uv** | Python Runtime | `0.12.10` | High-speed Python package manager for data contracts in `contracts/`. |
| **Terraform** | IaC | `1.8.5` | Deploys substrate namespaces and base resources in `infra/terraform/`. |
| **kubectl** | Kubernetes | `1.36.4` | Primary CLI for interacting with the k3s cluster. |
| **Helm 3** | Kubernetes | `3.21.4` | Manages third-party chart releases (Bank-Vaults, External Secrets). |
| **Kustomize** | Kubernetes | `5.8.1` | Builds and validates multi-environment K8s overlays in `k8s/`. |
| **ArgoCD CLI** | GitOps | `3.5.2` | Manages GitOps App-of-Apps synchronization and health status. |
| **HashiCorp Vault CLI** | Security | `1.18.4` | Manages runtime secrets consumed by External Secrets Operator. |
| **k9s** | Observability | `0.51.0` | Terminal UI for real-time cluster monitoring and pod inspection. |
| **AWS CLI v2** | Cloud / FinOps | `2.36.40` | Tests AWS S3 interactions for the `$0.00` Free Tier cloud environment. |
| **OpenSSL** | Security | `3.5.5` | Inspects certificates, generates tokens, and debugs TLS connections. |

---

## 3. Step 2: Single-Node k3s Cluster Bootstrap

Bootstrap the resource-optimized single-node cluster directly using Linux systemd (no Docker or VMs):

```bash
make host-bootstrap
```

### What Happens During Bootstrap:
1. **Server Initialization with Production Hardening**:
   - Starts single-node `k3s` server on the host network with node name `k3s-node`.
   - Configures etcd secrets encryption at rest via AES-CBC (`/var/lib/rancher/k3s/server/cred/encryption-config.json`).
   - Disables default Traefik ingress (in favor of production Kong Gateway).
   - Extends NodePort range to `30000-40000` to support all operational UIs.
   - Symlinks `/usr/bin/k3s` and `/usr/bin/kubectl` for AlmaLinux `secure_path` compatibility.
2. **Dedicated Storage Pool Configuration**:
   - Prepares isolated host storage pool at `/data/k3s-storage`.
   - Configures k3s built-in `local-path-provisioner` to store all persistent volumes in `/data/k3s-storage`.
3. **Multi-Workload Role Labeling**:
   - Labels `k3s-node` with `control-plane`, `master`, `worker`, `streaming`, and `batch`.
   - Ensures all manifests with `nodeSelector` (e.g. Vault requiring `control-plane`) schedule seamlessly.
4. **Kubeconfig & Context Setup**:
   - Configures cluster context `k3s-data-platform` in `/etc/rancher/k3s/k3s.yaml`.
   - Automatically synchronizes kubeconfig to `~/.kube/config` and persists `KUBECONFIG` in `~/.bashrc`.

### Verify Cluster Health

```bash
# 1. Verify single-node is Ready with all roles
kubectl get nodes -o wide

# Expected Output:
# NAME       STATUS   ROLES                                         AGE   VERSION        INTERNAL-IP     EXTERNAL-IP   OS-IMAGE
# k3s-node   Ready    batch,control-plane,master,streaming,worker   ...   v1.36.4+k3s1   172.31.x.x      <none>        AlmaLinux 10.2

# 2. Verify core system pods are running
kubectl get pods -n kube-system
```

---

## 4. Step 3: Platform Substrate Provisioning (Terraform IaC)

The platform infrastructure is partitioned into shared reusable modules (`infra/terraform/modules/`) provisioned via Terraform:

```mermaid
flowchart LR
    subgraph Terraform["infra/terraform/envs/self_manage/"]
        M1[k8s_base: Namespaces & Pod Security Standards]
        M2[storage_base: Local Storage Pool at /data/k3s-storage]
        M3[gitops_argo: ArgoCD Core Deployment]
    end

    Terraform --> K8S[Target: Local Single-Node k3s Cluster]
```

### Provision Local Infrastructure

```bash
# 1. Initialize Terraform providers (Kubernetes, Helm)
make infra-init

# 2. Review the execution plan for local self_manage environment
make infra-plan

# 3. Apply the substrate infrastructure
make infra-apply
```

### Cloud FinOps Validation (Strict $0.00 AWS Free Tier)
To inspect the dual-target cloud environment without incurring costs:
```bash
make infra-plan-aws
```
*Guarantees zero cloud charges: Provisions 4 AES-256 S3 buckets and a zero-cost S3 Gateway VPC Endpoint (eliminating NAT Gateway hourly charges).*

---

## 5. Step 4: GitOps Application Bootstrap (ArgoCD App-of-Apps)

The platform utilizes fully declarative GitOps via the ArgoCD App-of-Apps pattern. HashiCorp Vault, the External Secrets Operator, runtime secrets, datastores, and applications are orchestrated in deterministic dependency order using **ArgoCD Sync Waves**:

```mermaid
flowchart TD
    subgraph WaveNeg2["Sync Wave -2: Security Operators"]
        BVO[Bank-Vaults Operator]
        ESO[External Secrets Operator]
    end

    subgraph WaveNeg1["Sync Wave -1: Vault & Automated Seeding"]
        V[Vault StatefulSet :38200]
        CSS[ClusterSecretStore]
        SEED[In-Cluster Secret Seeder Job]
    end

    subgraph Wave0["Sync Wave 0: Core Platform Engines"]
        RP[Redpanda Kafka :9092]
        MIN[MinIO Lakehouse :9000]
        PG[PostgreSQL :5432]
        KONG[Kong Gateway :30000]
        AW[Argo Workflows :32746]
        FL[Apache Flink :38081]
    end

    subgraph Wave1["Sync Wave 1: Autonomous Microservices"]
        ORD[order-service :8080]
        RDR[rider-service :8081]
        STR[stream-ingestor :8082]
        SET[settlement-engine CronJob]
        TRF[traffic-generator]
    end

    subgraph Wave2["Sync Wave 2: SRE Observability"]
        GRAF[Grafana Dashboard :30300]
        PROM[Prometheus TSDB :9090]
        ALT[Alertmanager :9093]
    end

    WaveNeg2 --> WaveNeg1
    WaveNeg1 --> Wave0
    Wave0 --> Wave1
    Wave1 --> Wave2
```

### Deploy the Root Application

Apply the master App-of-Apps manifest to trigger the complete cluster deployment:

```bash
# 1. Deploy the dev environment root application
kubectl apply -f argocd/dev/root.yaml

# 2. Retrieve initial ArgoCD admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
echo ""

# 3. Verify App-of-Apps synchronization (ArgoCD CLI connects via HTTPS NodePort 30443)
argocd login localhost:30443 --username admin --password <password> --insecure --skip-test-tls --grpc-web
argocd app list
```

### Verify ExternalSecret Synchronization

Once workloads are deployed, verify that the External Secrets Operator has automatically pulled credentials from Vault and synthesized native Kubernetes `Secret` objects:

```bash
# Verify ExternalSecret CR status (should show 'SecretSynced: True')
kubectl get externalsecrets -A

# Verify synthesized Kubernetes secrets
kubectl get secrets -n apps
kubectl get secrets -n platform
```

---

## 6. Step 5: (Optional) Secret Inspection & Manual Re-Seeding

Default credentials for development are seeded automatically during **Sync Wave -1** by the `vault-secret-seeder` Kubernetes Job. 

### Automated Re-Seeding

To manually re-populate or update secrets in Vault from the terminal:

```bash
make seed-secrets
```

### Inspect Stored Secrets

To query and inspect secrets stored inside Vault KV v2:

```bash
export VAULT_ADDR="http://localhost:38200"
export VAULT_TOKEN=$(kubectl get secret vault-unseal-keys -n vault-system -o jsonpath="{.data.vault-root}" | base64 -d)

# List all secret paths
vault kv list secret/
vault kv list secret/apps/
vault kv list secret/platform/
vault kv list secret/observability/

# Inspect a specific secret (e.g. order-service)
vault kv get secret/apps/order-service
```

---

## 7. Step 6: (Optional) Local Validation & Contract Linting

> [!NOTE]
> **CI/CD Automation:** In standard GitOps operations, **building container images locally is unnecessary**. The GitHub Actions CI/CD pipeline ([.github/workflows/cd-build.yaml](file:///c:/Users/x/work/data-platfrom/.github/workflows/cd-build.yaml)) automatically compiles Go binaries, builds distroless container images, and pushes them to `ghcr.io` upon every push to `main`.
> 
> The commands below are **local developer convenience targets** used to test schema changes and verify syntax locally before committing:

```bash
# 1. (Recommended) Validate Data Contract backward-compatibility
make test-contracts

# 2. (Optional) Fast local Go syntax/type check without waiting for CI (outputs to /dev/null)
make build-apps

# 3. (Optional) Build Docker images locally (only needed for offline/custom image development)
make docker-build
```

---

## 8. Step 7: Verification, Testing & Operational Web UIs

### Run Complete Test Suite

```bash
# Run unit and contract tests across all domains
make test

# Run end-to-end verification smoke test
make verify
```

### Launch Interactive Cluster Monitor

```bash
k9s
```

### Access Platform Web UIs

Run `make dashboard` to view all active endpoints:

| Subsystem | Service | Local Web UI URL | Purpose |
| :--- | :--- | :--- | :--- |
| **API Ingress** | Kong API Gateway | `http://localhost:30000/api/v1` | Public API ingress for mobile orders and GPS pings. |
| **GitOps Engine** | ArgoCD | `https://localhost:30443` | Continuous Delivery & App-of-Apps sync status (HTTP: 30080). |
| **Batch DAG Engine** | Argo Workflows | `http://localhost:32746` | Daily financial settlement & reconciliation DAGs. |
| **Stream Engine** | Apache Flink | `http://localhost:38081` | Real-time streaming metrics & CEP jobs. |
| **Observability** | Grafana | `http://localhost:30300` | SRE overview, gold financial metrics, system health. |
| **Secrets Engine** | HashiCorp Vault | `http://localhost:38200` | KV v2 secrets management and audit log. |

---

## 10. Step 9: Clean Cluster Teardown & Reset

To cleanly uninstall the cluster, terminate runtime processes, and purge storage mounts without leaving lingering host artifacts:

```bash
make host-teardown
```

### Teardown Cleans Up:
- Stops and disables all k3s systemd services (`k3s*.service`).
- Safely terminates leftover container runtimes and containerd-shims.
- Unmounts any remaining runtime, container, and kubelet mounts under `/run/k3s`, `/var/lib`, and `/data/k3s-storage`.
- Cleans up state directories (`/var/lib/rancher`, `/run/k3s`, `/data/k3s-storage/*`).
- Cleans up `~/.kube/config` and removes `/usr/bin/k3s` and `/usr/bin/kubectl` symlinks.
- Automatically restores terminal TTY attributes (`stty sane`).

---

## 11. Troubleshooting & SRE Runbooks

### Issue 1: `sudo: k3s: command not found`
- **Cause**: AlmaLinux-10 enforces a restricted `secure_path` in `/etc/sudoers` that strips `/usr/local/bin`.
- **Fix**: Re-run `make install-tools` or re-create the symlinks:
  ```bash
  sudo ln -sf /usr/local/bin/k3s /usr/bin/k3s
  sudo ln -sf /usr/local/bin/kubectl /usr/bin/kubectl
  ```

### Issue 2: Terminal Echo Lost or Text Input Invisible
- **Cause**: If an interactive process or sudo prompt was interrupted before restoring TTY modes, the terminal echo flag may remain disabled.
- **Fix**: Execute the following command in the terminal and press Enter (the shell will accept input even if characters are not displayed on screen):
  ```bash
  stty sane
  ```

### Issue 3: Systemd Not Running as PID 1 in WSL
- **Cause**: WSL2 was started without systemd enabled in `/etc/wsl.conf`.
- **Fix**: Add the following to `/etc/wsl.conf` and restart WSL from PowerShell (`wsl --shutdown`):
  ```ini
  [boot]
  systemd=true
  ```

### Issue 4: Localhost NodePort Unreachable from Windows
- **Cause**: WSL2 networking mode or Windows firewall blocking localhost forwarding.
- **Fix**: Ensure the service NodePort is listening (`kubectl get svc -A`) and verify socket binding:
  ```bash
  ss -tulpn | grep -E '30000|30080|30443|30300'
  ```
