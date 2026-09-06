# Workflow: IaC Platform Provisioning & GitOps Bootstrap

**Workflow ID**: `iac-platform-provisioning`  
**Target Role**: Data Platform Engineer  
**Status**: DRAFT - Ready for Implementation  
**Memory Budget**: < 2.5 GB total for platform control plane & baseline services  

---

## 1. Objective
Declare, provision, and maintain the base infrastructure for the Cloud-Native Data Platform. This workflow sets up native Kubernetes (`k3s` in WSL2), an isolated Cloud-Native Storage Manager to protect host system storage from disk bloat, modular Terraform (`terraform/envs/self_manage` and `terraform/envs/free_tier_aws`), and the ArgoCD GitOps controller to reconcile data services.

---

## 2. Trigger
- **Manual Trigger**: Developer runs `make infra-bootstrap` or `make infra-plan`.
- **Event Trigger (CI)**: Git pull request or push modifying any path under `infra/**` or `k8s/**`.

---

## 3. Architecture & Boundaries

### 3.1 Host & Cluster Environment (3-Node Topology)
- **Host Engine**: Native `k3s` running as systemd services inside WSL2 (`AlmaLinux-10`). No Docker-in-Docker layer.
- **Node Roles & Topology**:
  - `k3s-control-plane`: Control plane components, ArgoCD Core, Argo Workflows Controller, Prometheus, Grafana, Longhorn Manager.
  - `k3s-worker-stream` (Label: `workload=streaming`): Kong API Ingress Gateway, Redpanda Streaming Broker, Apache Flink Session Cluster.
  - `k3s-worker-batch` (Label: `workload=batch`): MinIO 3-Tier Lakehouse, Apache Spark on K8s (ephemeral Driver + Executor pods).
- **Namespaces**:
  - `platform`: Core data plane engines (PostgreSQL, Redpanda, MinIO, Apache Flink, Kong Gateway, HashiCorp Vault).
  - `apps`: In-cluster running domain Go applications (order-service, rider-service, stream-ingestor, settlement-engine, traffic-generator).
  - `observability`: Dedicated observability stack (Prometheus, Alertmanager, Loki, Jaeger, Grafana).
  - `argocd`: ArgoCD GitOps control plane and application CRDs.
  - `argo-workflow`: Argo Workflows batch DAG execution engine and UI.
  - `longhorn-system`: Longhorn distributed storage controller, CSI plugin, and UI.

### 3.2 Storage Management (Longhorn CSI Engine & Isolation)
To guarantee zero pollution of host root system directories (`/` and `/var/lib`), storage is handled by **Longhorn** running across our 3-node cluster in namespace `longhorn-system`:
- **CSI Provisioner**: `driver.longhorn.io`
- **Isolated Storage Path**: Configured strictly to `/data/k3s-storage` via Longhorn `default-data-path` setting to protect the OS root partition.
- **StorageClass**: `longhorn-isolated` (default).
- **Multi-Node Volume Resilience**: With 3 nodes, Longhorn demonstrates true distributed volume replication (`numberOfReplicas: 2`) across worker nodes.
- **Longhorn UI**: Exposed at `http://localhost:30088` for volume health, IOPS, and snapshot inspection.
- **Features**: Dedicated CSI block device provisioning, dynamic volume expansion, volume snapshots/backups, and Prometheus disk I/O metrics.

### 3.3 Resource Limits Profile (< 3.8 GB RAM Continuous Baseline)
| Component | Subsystem | CPU Limit | Memory Limit | PVC Size | Node Target | Lifecycle |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **Kong Gateway** | API Ingress Proxy | 200m | 250Mi | None (DB-less) | `k3s-worker-stream` | Continuous |
| **Redpanda** | Kafka Streaming Broker | 500m | 512Mi | 2Gi (`longhorn-isolated`) | `k3s-worker-stream` | Continuous |
| **Apache Flink (JM+TM)**| Stream Compute Engine | 500m | 896Mi | Ephemeral | `k3s-worker-stream` | Continuous |
| **Longhorn Manager & CSI** | Storage CSI & UI | 300m | 512Mi | Dedicated Pool (`/data/k3s-storage`) | All Nodes | Continuous |
| **ArgoCD Core** | GitOps Deployment Controller| 200m | 200Mi | None (Stateless) | `k3s-control-plane` | Continuous |
| **Argo Workflows** | Batch DAG Orchestrator & UI | 200m | 180Mi | None (Stateless) | `k3s-control-plane` | Continuous |
| **MinIO (S3 Engine)** | 3-Tier Lakehouse Object Store| 250m | 384Mi | 4Gi (`longhorn-isolated`) | `k3s-worker-batch` | Continuous |
| **Prometheus + Grafana** | SRE Telemetry & Dashboards | 300m | 384Mi | 1.5Gi (`longhorn-isolated`)| `k3s-control-plane` | Continuous |
| **Apache Spark on K8s** | Batch Reconciliation Engine | 1000m | 1.2Gi | Ephemeral Worker | `k3s-worker-batch` | **Ephemeral (Runs ~2m daily)** |

### 3.4 Production Networking & Zero-Trust Policies
- **Edge Ingress**: Kong Gateway terminates both **REST JSON** (`/api/v1/orders`) and **gRPC / HTTP/2** (`/api/v1/riders.telemetry/StreamLocation`).
- **Zero-Trust NetworkPolicies**: Default-deny ingress across `platform`; strictly permits:
  - `kong` -> `redpanda` on port `9092`
  - `flink` -> `redpanda` on port `9092` & `minio` on port `9000`
  - `spark` -> `minio` on port `9000`
  - `prometheus` -> metrics scraping ports across all components.
- **Sidecar-less Data Plane**: Bypasses heavy sidecar proxies (Envoy) on Redpanda, Flink, and Spark to eliminate latency and memory double-buffering.
- **DNS Resilience**: `NodeLocal DNSCache` daemonset deployed to worker nodes + JVM DNS caching (`-Dnetworkaddress.cache.ttl=60`) to prevent CoreDNS socket starvation.
- **Cloud FinOps**: AWS S3 Gateway VPC Endpoint declared in `terraform/envs/free_tier_aws/` for $0.00 data transfer fees.

---

## 4. Execution Steps (Autonomous Pipeline)

### Step 1: 3-Node Cluster & Storage Isolation Pre-check
```bash
# Verify k3s control plane is active
systemctl is-active k3s || curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server --disable=traefik --disable=local-storage --node-name=k3s-control-plane" sh -

# Extract node join token
NODE_TOKEN=$(sudo cat /var/lib/rancher/k3s/server/node-token)

# Join Worker 1: Streaming Node
sudo k3s agent --server=https://127.0.0.1:6443 --token=$NODE_TOKEN --node-name=k3s-worker-stream --node-label workload=streaming &

# Join Worker 2: Batch Node
sudo k3s agent --server=https://127.0.0.1:6443 --token=$NODE_TOKEN --node-name=k3s-worker-batch --node-label workload=batch &

# Create isolated data mount directory across nodes
sudo mkdir -p /data/k3s-storage
sudo chmod 777 /data/k3s-storage
```

### Step 2: Longhorn Storage Engine Installation
Deploy Longhorn via Helm with isolated data path:
```bash
helm repo add longhorn https://charts.longhorn.io
helm repo update
helm upgrade --install longhorn longhorn/longhorn \
  --namespace longhorn-system \
  --create-namespace \
  --set defaultSettings.defaultDataPath="/data/k3s-storage" \
  --set defaultSettings.defaultReplicaCount=1 \
  --set persistence.defaultClass=true \
  --set persistence.defaultClassReplicaCount=1
```
- Registers `driver.longhorn.io` as the active CSI driver.
- Sets `longhorn-isolated` as the default `StorageClass`.
- Verifies storage class readiness via `kubectl get storageclass`.

### Step 3: Terraform Plan Generation ("Push Right")
The runner executes:
```bash
cd terraform/envs/self_manage
terraform init
terraform fmt -check
terraform validate
terraform plan -out=tfplan.binary
```
The workflow intercepts `tfplan.binary` and generates a structured **Execution Brief** before any changes are applied.

---

## 5. Checkpoint & Decision Brief

### Checkpoint Rule
Maximal work is performed autonomously (linting, syntax validation, dependency checking, plan generation). Execution pauses ONLY for human review of the concise Execution Brief.

### Brief Format
```markdown
### 📋 Terraform Infrastructure Execution Brief
- **Target Environment**: `envs/self_manage` (Native k3s + Longhorn CSI Storage Substrate)
- **Namespaces Managed**: `platform`, `apps`, `observability`, `argocd`, `argo-workflow`, `longhorn-system`
- **Storage CSI Driver**: `driver.longhorn.io` (`longhorn-isolated` pinned to `/data/k3s-storage`)
- **GitOps Bootstrap**: ArgoCD Core (`NodePort: 30080`) & Argo Workflows Controller (`NodePort: 32746`)
- **Declarative GitOps Handoff**:
  - API Ingress: Kong Gateway API (`k8s/platform/kong`)
  - Streaming Broker & Topics: Redpanda (`k8s/platform/redpanda`) with native `rpk` topic init
  - Object Storage: MinIO (`k8s/platform/minio`) with native `mc` bucket init
  - Compute & RBAC: Flink Session Cluster (`k8s/platform/flink`) & Spark DAGs (`k8s/platform/argo-workflows`)
- **Resource Summary**:
  - ➕ To Add: Substrate resources (Namespaces, StorageClass, ArgoCD/Workflows Helm releases)
  - 🔄 To Modify: 0 resources
  - ➖ To Destroy: 0 resources
- **Storage Allocation**: Pool `/data/k3s-storage` (Strictly isolated from system root)
- **Status**: Plan succeeded without errors.
- **Action Required**: Approve Apply [y/N]?
```

---

## 6. Day-2 GitOps Sync (ArgoCD)

Once approved and applied:
1. Terraform outputs the operational web endpoints:
   - **Kong Ingress Gateway**: `http://localhost:30000/api/v1`
   - **ArgoCD GitOps UI**: `http://localhost:30080`
   - **Argo Workflows UI**: `http://localhost:32746`
   - **Longhorn Storage UI**: `http://localhost:30088`
   - **Apache Flink Dashboard**: `http://localhost:38081`
   - **Grafana SRE Dashboard**: `http://localhost:30300`
   - **Jaeger Tracing UI**: `http://localhost:31686`
   - **Vault Secrets UI**: `http://localhost:38200`
2. ArgoCD App-of-Apps (`argocd/dev/root.yaml`) synchronizes autonomous AppProjects and Applications:
   - **Platform Infrastructure (`argocd/dev/platform/`)**:
     - `kong/`, `postgres/`, `redpanda/`, `flink/`, `argo-workflows/`, `minio/`, `vault/`, `prometheus/`, `alertmanager/`, `loki/`, `jaeger/`, `grafana/`, `network-policies/`
   - **Real Running Workloads (`argocd/dev/apps/`)**:
     - `order-service/`, `rider-service/`, `stream-ingestor/`, `settlement-engine/`, `traffic-generator/`
3. ArgoCD continuously monitors cluster state and detects/reverts any manual out-of-band drifts.

---

## 7. Automated Verification & Definition of Done

An implementer agent verifies this workflow is complete when all assertions in `scripts/verify-infra.sh` pass:

1. **Cluster Assertion**: `kubectl get nodes` returns `Ready`.
2. **Longhorn CSI Assertion**: `kubectl get pods -n longhorn-system` are all `Running`, and Longhorn UI responds at `http://localhost:30088`.
3. **Storage Isolation Assertion**: `kubectl get pvc -n platform` shows volumes bound using `driver.longhorn.io` (`longhorn-isolated`), and block replicas exist exclusively in `/data/k3s-storage/` without touching `/var/lib`.
4. **GitOps Sync Assertion**: `argocd app list` shows all core platform applications in `Synced` and `Healthy` state.
5. **Memory Constraint Assertion**: Total platform baseline memory usage does not exceed 3.8 GB RAM.
6. **Teardown Assertion**: `make infra-destroy` cleanly releases all PVCs and removes namespaces without leaving dangling pods.
