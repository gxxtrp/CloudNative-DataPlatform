"""
NYC TLC Yellow Taxi Public Batch Ingestion

Downloads monthly trip record Parquet files from NYC TLC CDN,
verifies data integrity via SHA256 checksum, generates an ingestion
manifest, and uploads both to the GCS Bronze Data Lake.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import logging
import os
import sys
import urllib.request
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, Protocol

logging.basicConfig(
    level=logging.INFO,
    format='{"time":"%(asctime)s","level":"%(levelname)s","message":"%(message)s"}',
)
logger = logging.getLogger("public-batch-ingest")

TLC_BASE_URL = "https://d37ci6vzurychx.cloudfront.net/trip-data"
STREAM_CHUNK_SIZE_BYTES = 8 * 1024 * 1024  # 8 MB streaming chunks


# ---------------------------------------------------------------------------
# Domain: Pure Business Rules & Calculations
# ---------------------------------------------------------------------------

def format_month(month: str | int) -> str:
    """Format month to zero-padded two-digit string."""
    m_int = int(month)
    if not 1 <= m_int <= 12:
        raise ValueError(f"Month must be between 1 and 12, got: {month}")
    return f"{m_int:02d}"


def build_source_filename(year: str, month: str | int) -> str:
    """Construct canonical TLC Yellow Taxi parquet filename."""
    return f"yellow_tripdata_{year}-{format_month(month)}.parquet"


def build_source_url(filename: str) -> str:
    """Build full CDN URL for downloading source data."""
    return f"{TLC_BASE_URL}/{filename}"


def build_bronze_gcs_prefix(year: str, month: str | int) -> str:
    """Construct partitioned storage prefix for the Bronze Lake tier."""
    return f"nyc-taxi/yellow/year={year}/month={format_month(month)}"


def compute_file_sha256(file_path: Path) -> str:
    """Compute SHA256 hex digest of a local file using streamed chunks."""
    hasher = hashlib.sha256()
    with open(file_path, "rb") as stream:
        while chunk := stream.read(STREAM_CHUNK_SIZE_BYTES):
            hasher.update(chunk)
    return hasher.hexdigest()


@dataclass(frozen=True)
class IngestionManifest:
    """Immutable record of an ingested batch data asset."""
    dataset: str
    year: str
    month: str
    source_url: str
    destination_gcs: str
    byte_size: int
    sha256_checksum: str
    ingested_at_utc: str
    tier: str = "bronze"
    format: str = "parquet"

    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)


def build_manifest(
    *,
    dataset: str,
    year: str,
    month: str | int,
    source_url: str,
    destination_gcs_uri: str,
    byte_size: int,
    sha256_checksum: str,
) -> Dict[str, Any]:
    """Factory creating an ingestion manifest dictionary."""
    manifest = IngestionManifest(
        dataset=dataset,
        year=str(year),
        month=format_month(month),
        source_url=source_url,
        destination_gcs=destination_gcs_uri,
        byte_size=byte_size,
        sha256_checksum=sha256_checksum,
        ingested_at_utc=datetime.now(timezone.utc).isoformat(),
    )
    return manifest.to_dict()


# ---------------------------------------------------------------------------
# Ports (Interfaces / Protocols)
# ---------------------------------------------------------------------------

class FileDownloader(Protocol):
    """Port for streaming remote files to local filesystem."""
    def download(self, url: str, target_path: Path) -> int:
        ...


class StorageUploader(Protocol):
    """Port for persisting local files to object storage."""
    def upload(self, local_path: Path, bucket_name: str, destination_blob: str) -> str:
        ...


# ---------------------------------------------------------------------------
# Adapters (Implementations)
# ---------------------------------------------------------------------------

class UrllibFileDownloader:
    """Standard library HTTP downloader with chunked streaming."""

    def download(self, url: str, target_path: Path) -> int:
        target_path.parent.mkdir(parents=True, exist_ok=True)
        request = urllib.request.Request(
            url,
            headers={"User-Agent": "CloudNative-DataPlatform-Ingest/1.0"},
        )
        total_bytes = 0
        with urllib.request.urlopen(request, timeout=60) as response:
            with open(target_path, "wb") as out_file:
                while chunk := response.read(STREAM_CHUNK_SIZE_BYTES):
                    out_file.write(chunk)
                    total_bytes += len(chunk)
        return total_bytes


class GCSStorageUploader:
    """Google Cloud Storage adapter with lazy SDK resolution."""

    def upload(self, local_path: Path, bucket_name: str, destination_blob: str) -> str:
        from google.cloud import storage  # Lazy import decouples domain & tests from SDK
        client = storage.Client()
        bucket = client.bucket(bucket_name)
        blob = bucket.blob(destination_blob)
        blob.upload_from_filename(str(local_path))
        return f"gs://{bucket_name}/{destination_blob}"


# ---------------------------------------------------------------------------
# Use Case: Batch Ingestion Orchestration
# ---------------------------------------------------------------------------

class BatchIngestionUseCase:
    """Application use case orchestrating batch download, verification, and publication."""

    def __init__(
        self,
        downloader: FileDownloader | None = None,
        storage_uploader: StorageUploader | None = None,
    ):
        self._downloader = downloader or UrllibFileDownloader()
        self._storage = storage_uploader or GCSStorageUploader()

    def execute(
        self,
        year: str,
        month: str | int,
        bronze_bucket: str,
        work_dir: Path,
    ) -> Dict[str, Any]:
        """Execute end-to-end batch ingestion workflow."""
        filename = build_source_filename(year, month)
        source_url = build_source_url(filename)
        prefix = build_bronze_gcs_prefix(year, month)
        local_data_file = work_dir / filename
        local_manifest_file = work_dir / f"{filename}.manifest.json"

        logger.info(f"Downloading {filename} from {source_url}...")
        byte_size = self._downloader.download(source_url, local_data_file)
        logger.info(f"Downloaded {byte_size} bytes. Verifying SHA256 checksum...")

        sha256_hash = compute_file_sha256(local_data_file)
        logger.info(f"Computed SHA256: {sha256_hash}")

        data_blob_path = f"{prefix}/{filename}"
        logger.info(f"Uploading data asset to gs://{bronze_bucket}/{data_blob_path}...")
        destination_uri = self._storage.upload(local_data_file, bronze_bucket, data_blob_path)

        manifest = build_manifest(
            dataset="nyc-yellow-taxi",
            year=year,
            month=month,
            source_url=source_url,
            destination_gcs_uri=destination_uri,
            byte_size=byte_size,
            sha256_checksum=sha256_hash,
        )

        with open(local_manifest_file, "w", encoding="utf-8") as f:
            json.dump(manifest, f, indent=2)

        manifest_blob_path = f"{prefix}/{filename}.manifest.json"
        logger.info(f"Uploading manifest to gs://{bronze_bucket}/{manifest_blob_path}...")
        self._storage.upload(local_manifest_file, bronze_bucket, manifest_blob_path)

        logger.info(f"Batch ingestion completed: {destination_uri}")
        return manifest


def run_ingestion(
    year: str,
    month: str | int,
    bronze_bucket: str,
    work_dir: Path,
    downloader: FileDownloader | None = None,
    storage_uploader: StorageUploader | None = None,
) -> Dict[str, Any]:
    """Convenience function preserving backward compatibility."""
    use_case = BatchIngestionUseCase(downloader=downloader, storage_uploader=storage_uploader)
    return use_case.execute(year, month, bronze_bucket, work_dir)


# ---------------------------------------------------------------------------
# Composition Root / CLI
# ---------------------------------------------------------------------------

def parse_args() -> argparse.Namespace:
    """Parse CLI input arguments."""
    parser = argparse.ArgumentParser(description="NYC TLC Yellow Taxi Public Batch Ingestion")
    parser.add_argument("--year", required=True, help="Year of dataset (e.g. 2024)")
    parser.add_argument("--month", required=True, help="Month of dataset (e.g. 01)")
    parser.add_argument(
        "--bucket",
        default=os.environ.get("BRONZE_BUCKET", "sbx-workload-poc-508107-lake-bronze-dev"),
        help="Target Bronze GCS bucket name",
    )
    parser.add_argument(
        "--work-dir",
        default="/tmp/ingest",
        help="Local working directory for streaming and hashes",
    )
    return parser.parse_args()


def main() -> None:
    """CLI entrypoint."""
    args = parse_args()
    try:
        manifest = run_ingestion(
            year=args.year,
            month=args.month,
            bronze_bucket=args.bucket,
            work_dir=Path(args.work_dir),
        )
        print(json.dumps(manifest, indent=2))
    except Exception as err:
        logger.error(f"Ingestion failed: {err}", exc_info=True)
        sys.exit(1)


if __name__ == "__main__":
    main()
