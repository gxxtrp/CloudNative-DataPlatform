# Workflow: Lakehouse Small-File Compaction & Storage SRE Maintenance

**Workflow ID**: `lakehouse-compaction-maintenance`  
**Target Role**: Data Platform Engineer  
**Status**: DRAFT - Ready for Implementation  
**Category**: Storage Reliability, Compaction & FinOps  

---

## 1. Objective
Solve the streaming "small-files problem" in Apache Iceberg on MinIO/S3. The ingestion worker commits micro-batches every 5 seconds, producing hundreds of tiny Parquet files. This autonomous maintenance engine compacts small files into optimal partitions, expires stale Iceberg snapshots, and purges orphaned objects to reclaim storage space in `/data/k3s-storage` and sustain query performance.

---

## 2. Trigger
- **Schedule Trigger**: Kubernetes CronJob (`Platform-iceberg-compactor`) executed every **30 minutes**.
- **Threshold Trigger**: Autonomous trigger when any partition exceeds **30 uncompacted Parquet files**.
- **Manual Trigger**: `uv run python scripts/compact_tables.py --table silver_orders_state`.

---

## 3. Storage Scope & Compaction Policies
| Table | Bucket | Target Parquet Size | Snapshot Retention | Orphan Purge Window |
| :--- | :--- | :--- | :--- | :--- |
| `bronze_orders_raw` | `s3://Platform-bronze-lakehouse/` | 64 MiB | 3 Days | 24 Hours |
| `silver_orders_state` | `s3://Platform-silver-lakehouse/` | 128 MiB | 7 Days | 24 Hours |
| `silver_rider_telemetry`| `s3://Platform-silver-lakehouse/` | 128 MiB | 3 Days | 24 Hours |

---

## 4. Execution Steps (Autonomous SRE Maintenance Pipeline)

```
        ┌────────────────────────────────────────────────────────┐
        │ CronJob / Threshold Fires `compact_tables.py`          │
        └───────────────────────────┬────────────────────────────┘
                                    │
                                    ▼
        ┌────────────────────────────────────────────────────────┐
        │ Step 1: Scan Table Manifests for Small Files (< 32MiB) │
        └───────────────────────────┬────────────────────────────┘
                                    │
                                    ▼
        ┌────────────────────────────────────────────────────────┐
        │ Step 2: Read Small Files via DuckDB / PyIceberg &       │
        │ Write Consolidated Target Parquet (64-128MiB)          │
        └───────────────────────────┬────────────────────────────┘
                                    │
                                    ▼
        ┌────────────────────────────────────────────────────────┐
        │ Step 3: Atomic Iceberg Metadata Commit:                │
        │ Replace small file references with new compacted files │
        └───────────────────────────┬────────────────────────────┘
                                    │
                                    ▼
        ┌────────────────────────────────────────────────────────┐
        │ Step 4: Snapshot Expiration & Orphan File Pruning      │
        │ Deletes expired Parquet files from `/data/k3s-storage` │
        └───────────────────────────┬────────────────────────────┘
                                    │
                                    ▼
        ┌────────────────────────────────────────────────────────┐
        │ Step 5: Emit Prometheus Metrics & SRE Log Report       │
        └────────────────────────────────────────────────────────┘
```

### Step 1: Small File Identification
The worker inspects active snapshot metadata:
- Filters data files with size `< 32 MiB`.
- Groups files by partition (`event_date`, `geohash_prefix`).
- Skips partitions with fewer than 5 small files to avoid unnecessary I/O thrashing.

### Step 2: In-Memory Merge & Target Write
Using DuckDB / PyIceberg:
- Reads small files for the target partition.
- Writes consolidated Parquet files adhering to dictionary encoding, Snappy compression, and 128MB row group size.

### Step 3: Atomic Rewrite Commit
- Issues an Iceberg `RewriteFiles` action.
- Atomically swaps old data file pointers for the new compacted data file pointers in the metadata catalog.
- Zero downtime for concurrent streaming writes and analytical reads.

### Step 4: Storage Reclamation & Garbage Collection
- **Snapshot Expiry**: Evaluates table history and expires snapshots older than retention policy.
- **Orphan File Removal**: Scans S3/MinIO bucket path for Parquet files unreferenced by any valid snapshot manifest older than 24 hours and purges them, preventing disk exhaustion in `/data/k3s-storage`.

---

## 5. Checkpoint & Decision Brief
- **Operational Mode**: **Fully Autonomous**. Routine compactions require no human approval.
- **SRE Brief Logging**: On completion of each run, the compactor writes an execution summary to stdout and updates Prometheus metrics:
  - `lakehouse_compaction_duration_seconds`
  - `lakehouse_files_reduced_total` (small files before - compacted files after)
  - `lakehouse_bytes_reclaimed_total`
- **Safety Circuit Breaker**: If compaction causes an unexpected row-count mismatch (`count(before) != count(after)`), the transaction is immediately aborted, changes roll back, and a high-priority alert is emitted.

---

## 6. Automated Verification & Definition of Done

1. **Simulated Fragmentation**: Run streaming ingestion to generate 100+ tiny Parquet files across multiple partitions.
2. **Compaction Execution**: Execute `uv run python scripts/compact_tables.py --dry-run` followed by live execution.
3. **Integrity Assertion**: Row count query before and after compaction returns exact identical counts.
4. **Storage Reduction Assertion**: Total data file count drops by > 75%, and average file size approaches target size.
5. **Disk Reclaim Assertion**: Snapshot expiration removes old unreferenced files from `/data/k3s-storage`.
