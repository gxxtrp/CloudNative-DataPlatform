"""Lakehouse Streaming Ingestor Engine.

Consumes order lifecycle and rider telemetry events, validates them against
strict data contracts, writes valid records as Snappy columnar Parquet
to lakehouse-bronze with date/hour partitioning, and routes poison pills to DLQ.
"""

from __future__ import annotations

import argparse
import datetime
import json
from pathlib import Path
from typing import Any

import duckdb
import jsonschema


class LakehouseStreamIngestor:
    """Validates streaming events, writes Snappy Parquet micro-batches to Bronze, and routes to DLQ."""

    def __init__(
        self,
        bronze_base_path: str | Path,
        quarantine_base_path: str | Path,
        schemas_dir: str | Path | None = None,
    ) -> None:
        self.bronze_base_path = Path(bronze_base_path)
        self.quarantine_base_path = Path(quarantine_base_path)
        if schemas_dir is None:
            schemas_dir = Path(__file__).parent.parent / "schemas"
        self.schemas_dir = Path(schemas_dir)
        self.order_schema = self._load_schema("orders/orders.lifecycle.v1.json")
        self.rider_schema = self._load_schema("riders/riders.telemetry.v1.json")
        self.con = duckdb.connect(database=":memory:")

    def _load_schema(self, rel_path: str) -> dict[str, Any]:
        """Load a JSON schema by relative path."""
        p = self.schemas_dir / rel_path
        with open(p, "r", encoding="utf-8") as f:
            return json.load(f)

    def validate_event(self, event: dict[str, Any], event_type: str = "order") -> tuple[bool, str | None]:
        """Validate an event payload against its corresponding schema."""
        schema = self.order_schema if event_type == "order" else self.rider_schema
        validator = jsonschema.Draft7Validator(schema)
        errors = list(validator.iter_errors(event))
        if not errors:
            return True, None
        return False, f"Contract violation: {errors[0].message}"

    def process_events(
        self,
        events: list[dict[str, Any]],
        event_type: str = "order",
        batch_id: str | None = None,
    ) -> dict[str, Any]:
        """Process a batch of events: filter valid vs DLQ, write Parquet micro-batches and DLQ envelopes."""
        if not batch_id:
            batch_id = datetime.datetime.now(datetime.UTC).strftime("%Y%m%d_%H%M%S")

        valid_records: list[dict[str, Any]] = []
        quarantined_records: list[dict[str, Any]] = []

        now_utc = datetime.datetime.now(datetime.UTC)
        date_partition = now_utc.strftime("%Y-%m-%d")
        hour_partition = now_utc.strftime("%H")

        for event in events:
            is_valid, err_msg = self.validate_event(event, event_type=event_type)
            if is_valid:
                valid_records.append(event)
            else:
                envelope = {
                    "quarantine_id": f"dlq-{event.get('order_id', event.get('rider_id', 'unknown'))}-{now_utc.timestamp()}",
                    "source_topic": f"{event_type}s.lifecycle.v1" if event_type == "order" else "riders.telemetry.v1",
                    "error_reason": err_msg,
                    "quarantined_at": now_utc.isoformat(),
                    "raw_payload": event,
                }
                quarantined_records.append(envelope)

        parquet_file = None
        if valid_records:
            partition_dir = self.bronze_base_path / f"{event_type}s" / f"date={date_partition}" / f"hour={hour_partition}"
            partition_dir.mkdir(parents=True, exist_ok=True)
            parquet_file = str(partition_dir / f"batch_{batch_id}.parquet")
            tmp_json = partition_dir / f"tmp_{batch_id}.json"
            with open(tmp_json, "w", encoding="utf-8") as f:
                json.dump(valid_records, f)

            self.con.execute(
                f"""
                COPY (SELECT * FROM read_json_auto('{tmp_json.as_posix()}'))
                TO '{Path(parquet_file).as_posix()}'
                (FORMAT PARQUET, COMPRESSION 'SNAPPY');
                """
            )
            if tmp_json.exists():
                tmp_json.unlink()

        dlq_file = None
        if quarantined_records:
            dlq_dir = self.quarantine_base_path / f"{event_type}s" / f"date={date_partition}"
            dlq_dir.mkdir(parents=True, exist_ok=True)
            dlq_file = str(dlq_dir / f"dlq_{batch_id}.json")
            with open(dlq_file, "w", encoding="utf-8") as f:
                json.dump(quarantined_records, f, indent=2)

        return {
            "total_received": len(events),
            "valid_count": len(valid_records),
            "dlq_count": len(quarantined_records),
            "parquet_written": parquet_file,
            "dlq_written": dlq_file,
        }


def main() -> None:
    """CLI test runner for stream ingestor."""
    parser = argparse.ArgumentParser(description="Lakehouse Streaming Ingestion Engine")
    parser.add_argument("--bronze-path", default="data/lakehouse-bronze", help="Bronze lakehouse storage directory")
    parser.add_argument("--quarantine-path", default="data/lakehouse-quarantine", help="Quarantine storage directory")
    args = parser.parse_args()

    ingestor = LakehouseStreamIngestor(
        bronze_base_path=args.bronze_path,
        quarantine_base_path=args.quarantine_path,
    )

    sample_orders = [
        {
            "order_id": "ord-201",
            "customer_id": "cust-1",
            "merchant_id": "merch-somtum-der",
            "amount": 350.0,
            "currency": "THB",
            "status": "DELIVERED",
            "delivery_address": "Sukhumvit 55, Bangkok",
            "created_at": "2026-09-07T01:00:00Z",
            "updated_at": "2026-09-07T01:30:00Z",
        },
        {
            "order_id": "ord-202-poison",
            "customer_id": "cust-2",
            "merchant_id": "merch-somtum-der",
            "amount": -50.0,  # Violates minimum >= 0
            "currency": "THB",
            "status": "PLACED",
            "delivery_address": "Sathorn, Bangkok",
            "created_at": "2026-09-07T01:05:00Z",
            "updated_at": "2026-09-07T01:05:00Z",
        },
    ]

    result = ingestor.process_events(sample_orders, event_type="order")
    print(f"[STREAM_INGESTOR] Ingestion batch complete: {result}")


if __name__ == "__main__":
    main()
