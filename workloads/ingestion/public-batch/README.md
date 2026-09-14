# NYC TLC Yellow Taxi Public Batch Ingestion

Batch ingestion workload that downloads monthly NYC Taxi and Limousine Commission (TLC) trip record Parquet files from the public CDN, verifies their integrity via SHA256 checksums, constructs an immutable ingestion manifest, and publishes both to the GCS Bronze Data Lake.

## Architecture

This component follows **Clean Architecture** principles:

```text
┌─────────────────────────────────────────────────────────────┐
│ Frameworks & Drivers (CLI, GCS SDK, HTTP)                   │
│   ┌─────────────────────────────────────────────────────┐   │
│   │ Interface Adapters (UrllibFileDownloader, GCS)      │   │
│   │   ┌─────────────────────────────────────────────┐   │   │
│   │   │ Use Cases (BatchIngestionUseCase)           │   │   │
│   │   │   ┌─────────────────────────────────────┐   │   │   │
│   │   │   │ Domain & Entities (IngestionManifest)│   │   │   │
│   │   │   └─────────────────────────────────────┘   │   │   │
│   │   └─────────────────────────────────────────────┘   │   │
│   └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

- **Domain (`src/ingest.py`)**: Pure business logic (partition key formats, CDN URL construction, SHA256 hashing, immutable `IngestionManifest` dataclass). Zero external dependencies.
- **Ports (`FileDownloader`, `StorageUploader`)**: Abstract protocols defining the contracts for I/O operations.
- **Adapters (`UrllibFileDownloader`, `GCSStorageUploader`)**: Concrete implementations isolating external protocols and SDKs.
- **Use Case (`BatchIngestionUseCase`)**: Coordinates the sequential workflow: download -> verify checksum -> upload asset -> write manifest.
- **Composition Root / CLI (`main()`)**: Parses runtime arguments, binds dependencies, and executes the use case.

## Usage

### Local Execution

```bash
# Ingest January 2024 data into a Bronze bucket
python -m src.ingest --year 2024 --month 01 --bucket <MY_BRONZE_BUCKET>
```

### Running Unit Tests

Unit tests require zero external dependencies and run against Python 3.11+:

```bash
python3 -m unittest discover -s tests -v
```

### Docker Container Build

```bash
docker build -t asia-southeast1-docker.pkg.dev/sbx-workload-poc-508107/workload-images/public-batch-ingest:latest .
```

### Container Invocation

```bash
docker run --rm \
  -e GOOGLE_APPLICATION_CREDENTIALS=/secrets/sa.json \
  asia-southeast1-docker.pkg.dev/sbx-workload-poc-508107/workload-images/public-batch-ingest:latest \
  --year 2024 --month 01 --bucket sbx-workload-poc-508107-lake-bronze-dev
```
