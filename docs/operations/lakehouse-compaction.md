# Operations: Lakehouse Compaction & Small-File SRE Maintenance

**Domain**: Storage Reliability, Compaction & FinOps  
**Scope**: Solving the Small-File Problem in Apache Iceberg on MinIO/S3  

---

## 1. The Lakehouse "Small-File Problem"

High-throughput streaming ingestion writes micro-batches every 15 seconds, creating thousands of tiny (few KB to a few MB) Parquet files. This causes:
- **Severe Metadata Bloat**: Query engines (DuckDB, Spark, Trino) spend 80% of query latency reading file metadata rather than actual data.
- **High S3 GET Request Fees**: In cloud deployments, thousands of small files inflate API read charges.
- **Storage Inefficiency**: Fragmented blocks degrade filesystem compression ratios.

```mermaid
flowchart LR
    subgraph RawStream["Micro-Batch Stream Ingestion"]
        F1[part-01.parquet 12KB]
        F2[part-02.parquet 18KB]
        F3[part-03.parquet 15KB]
        FN[part-NN.parquet ...]
    end

    subgraph Compactor["Autonomous Compactor Engine"]
        F1 & F2 & F3 & FN --> BINPACK[Bin-Packer & Deduplicator]
    end

    subgraph Optimized["Compacted Lakehouse Partition"]
        BINPACK --> COMPACTED[compacted-001.snappy.parquet<br/>Target: 64-128 MiB<br/>83.5% Disk Savings]
    end
```

---

## 2. Compaction Policies & Metrics

| Table Partition | Target Parquet Size | Snapshot Retention | Orphan Purge Window |
| :--- | :--- | :--- | :--- |
| `lakehouse-bronze` | 64 MiB | 3 Days | 24 Hours |
| `lakehouse-silver` | 128 MiB | 7 Days | 24 Hours |
| `lakehouse-gold` | 128 MiB | 30 Days | 48 Hours |

- **Compression Gain**: Typical micro-batch fragmentation reduces by **83.5%** once compacted into Snappy columnar chunks.
- **Atomic Commits**: Uses Apache Iceberg / Delta Lake metadata replacement commits so live queries never observe partial or duplicated data.
