import hashlib
import io
import tempfile
import unittest
from pathlib import Path
from unittest.mock import MagicMock, patch

from src.ingest import (
    BatchIngestionUseCase,
    FileDownloader,
    StorageUploader,
    UrllibFileDownloader,
    build_bronze_gcs_prefix,
    build_manifest,
    build_source_filename,
    build_source_url,
    compute_file_sha256,
    format_month,
    run_ingestion,
)


class TestDomainRules(unittest.TestCase):
    """Unit tests for pure domain functions and validations."""

    def test_format_month_pads_single_digit(self):
        self.assertEqual(format_month(1), "01")
        self.assertEqual(format_month("1"), "01")
        self.assertEqual(format_month("09"), "09")
        self.assertEqual(format_month(12), "12")

    def test_format_month_rejects_out_of_range(self):
        with self.assertRaises(ValueError):
            format_month(0)
        with self.assertRaises(ValueError):
            format_month(13)
        with self.assertRaises(ValueError):
            format_month("invalid")

    def test_build_source_filename_formats_canonical_name(self):
        self.assertEqual(
            build_source_filename("2024", "1"),
            "yellow_tripdata_2024-01.parquet",
        )
        self.assertEqual(
            build_source_filename("2023", "12"),
            "yellow_tripdata_2023-12.parquet",
        )

    def test_build_source_url_constructs_valid_tlc_endpoint(self):
        filename = "yellow_tripdata_2024-01.parquet"
        expected = "https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_2024-01.parquet"
        self.assertEqual(build_source_url(filename), expected)

    def test_build_bronze_gcs_prefix_partitions_by_year_month(self):
        prefix = build_bronze_gcs_prefix("2024", "3")
        self.assertEqual(prefix, "nyc-taxi/yellow/year=2024/month=03")

    def test_compute_file_sha256_computes_exact_digest(self):
        with tempfile.TemporaryDirectory() as tmp_dir:
            test_file = Path(tmp_dir) / "sample.data"
            content = b"clean-architecture-data-platform-test-payload"
            test_file.write_bytes(content)

            expected_hash = hashlib.sha256(content).hexdigest()
            actual_hash = compute_file_sha256(test_file)

            self.assertEqual(actual_hash, expected_hash)

    def test_build_manifest_schema_compliance(self):
        manifest = build_manifest(
            dataset="nyc-yellow-taxi",
            year="2024",
            month="1",
            source_url="https://test.url/data.parquet",
            destination_gcs_uri="gs://test-bucket/data.parquet",
            byte_size=2048,
            sha256_checksum="mockedhash123",
        )

        self.assertEqual(manifest["dataset"], "nyc-yellow-taxi")
        self.assertEqual(manifest["year"], "2024")
        self.assertEqual(manifest["month"], "01")
        self.assertEqual(manifest["byte_size"], 2048)
        self.assertEqual(manifest["tier"], "bronze")
        self.assertEqual(manifest["format"], "parquet")
        self.assertIn("ingested_at_utc", manifest)


class TestUseCaseOrchestration(unittest.TestCase):
    """Unit tests for Use Case orchestration using mock ports."""

    def test_use_case_coordinates_download_hash_and_upload(self):
        mock_downloader = MagicMock(spec=FileDownloader)
        mock_storage = MagicMock(spec=StorageUploader)

        with tempfile.TemporaryDirectory() as tmp_dir:
            tmp_path = Path(tmp_dir)
            parquet_filename = "yellow_tripdata_2024-01.parquet"
            fake_content = b"fake-parquet-binary-stream"
            fake_hash = hashlib.sha256(fake_content).hexdigest()

            def fake_download(url: str, target_path: Path) -> int:
                target_path.write_bytes(fake_content)
                return len(fake_content)

            mock_downloader.download.side_effect = fake_download
            mock_storage.upload.side_effect = lambda local, bucket, blob: f"gs://{bucket}/{blob}"

            use_case = BatchIngestionUseCase(
                downloader=mock_downloader,
                storage_uploader=mock_storage,
            )

            manifest = use_case.execute(
                year="2024",
                month="01",
                bronze_bucket="test-lake-bronze",
                work_dir=tmp_path,
            )

            # Assert manifest contents
            self.assertEqual(manifest["dataset"], "nyc-yellow-taxi")
            self.assertEqual(manifest["sha256_checksum"], fake_hash)
            self.assertEqual(manifest["byte_size"], len(fake_content))
            self.assertEqual(
                manifest["destination_gcs"],
                "gs://test-lake-bronze/nyc-taxi/yellow/year=2024/month=01/yellow_tripdata_2024-01.parquet",
            )

            # Assert ports called correctly
            mock_downloader.download.assert_called_once_with(
                "https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_2024-01.parquet",
                tmp_path / parquet_filename,
            )
            # Storage upload called twice: once for data asset, once for manifest
            self.assertEqual(mock_storage.upload.call_count, 2)


class TestAdapters(unittest.TestCase):
    """Unit tests for infrastructure adapters."""

    @patch("urllib.request.urlopen")
    def test_urllib_file_downloader_streams_bytes_to_target(self, mock_urlopen: MagicMock):
        payload = b"streaming-test-bytes-chunk"
        mock_response = io.BytesIO(payload)
        mock_urlopen.return_value.__enter__.return_value = mock_response

        with tempfile.TemporaryDirectory() as tmp_dir:
            target_path = Path(tmp_dir) / "subfolder" / "downloaded.data"
            downloader = UrllibFileDownloader()

            downloaded_bytes = downloader.download(
                "https://test.example.com/test.parquet",
                target_path,
            )

            self.assertEqual(downloaded_bytes, len(payload))
            self.assertTrue(target_path.exists())
            self.assertEqual(target_path.read_bytes(), payload)


if __name__ == "__main__":
    unittest.main()
