"""DLQ Incident Triage & Safe Self-Healing Replay Engine.

Consumes quarantined poison pills from Managed Kafka or Cloud Storage quarantine,
clusters failure signatures (SCHEMA_DRIFT, CONSTRAINT_VIOLATION, MALFORMED_JSON),
runs dry-run contract re-validation, and provides safe remediation replay.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any

import jsonschema


class DLQTriageEngine:
    """Classifies quarantined dead-letter events and provides dry-run replay remediation."""

    def __init__(self, schemas_dir: str | Path | None = None) -> None:
        if schemas_dir is None:
            schemas_dir = Path(__file__).parent.parent / "schemas"
        self.schemas_dir = Path(schemas_dir)
        self.schemas: dict[str, dict[str, Any]] = {}
        self._load_schemas()

    def _load_schemas(self) -> None:
        """Load all JSON schemas for contract re-validation."""
        for schema_file in self.schemas_dir.glob("**/*.json"):
            try:
                with open(schema_file, "r", encoding="utf-8") as f:
                    data = json.load(f)
                    if isinstance(data, dict):
                        self.schemas[schema_file.name] = data
                        if "$id" in data:
                            self.schemas[data["$id"]] = data
                        if "title" in data:
                            self.schemas.setdefault(data["title"], data)
            except (json.JSONDecodeError, OSError):
                continue

    def classify_error(self, raw_record: str | bytes | dict[str, Any]) -> dict[str, Any]:
        """Classify a quarantined record into error signatures."""
        if isinstance(raw_record, (str, bytes)):
            try:
                payload = json.loads(raw_record)
            except json.JSONDecodeError as err:
                return {
                    "error_type": "MALFORMED_JSON",
                    "error_message": f"JSON syntax error: {err}",
                    "raw_payload": str(raw_record),
                    "can_auto_heal": False,
                }
        else:
            payload = raw_record

        # Check if wrapped in standard DLQ envelope
        inner_payload = payload.get("raw_payload", payload)
        if isinstance(inner_payload, str):
            try:
                inner_payload = json.loads(inner_payload)
            except json.JSONDecodeError:
                pass

        # Identify the explicit versioned contract. v1 remains the compatibility
        # default for records published before the versioned envelope exists.
        declared_version = inner_payload.get("schema_version", "1.0.0")
        version_match = (
            re.fullmatch(r"(\d+)\.\d+\.\d+", declared_version)
            if isinstance(declared_version, str)
            else None
        )
        if version_match is None:
            return {
                "error_type": "UNREGISTERED_SCHEMA",
                "error_message": "Payload declares an invalid schema_version",
                "payload": inner_payload,
                "can_auto_heal": False,
            }

        contract_major = version_match.group(1)
        target_schema = None
        if "order_id" in inner_payload or "total_amount_baht" in inner_payload:
            target_schema = self.schemas.get(f"orders.lifecycle.v{contract_major}.json")
        elif "rider_id" in inner_payload:
            target_schema = self.schemas.get(f"riders.telemetry.v{contract_major}.json")

        if not target_schema:
            return {
                "error_type": "UNREGISTERED_SCHEMA",
                "error_message": "Payload does not match any registered data contract",
                "payload": inner_payload,
                "can_auto_heal": False,
            }

        # Check for unregistered extra keys (Schema Drift detection)
        known_props = set(target_schema.get("properties", {}).keys())
        extra_keys = set(inner_payload.keys()) - known_props
        if extra_keys:
            return {
                "error_type": "SCHEMA_DRIFT",
                "error_message": f"Unregistered fields detected (Schema Drift): {list(extra_keys)}",
                "field": list(extra_keys),
                "payload": inner_payload,
                "can_auto_heal": False,
            }

        # Run schema validation
        validator = jsonschema.Draft7Validator(target_schema)
        errors = list(validator.iter_errors(inner_payload))

        if not errors:
            return {
                "error_type": "FALSE_POSITIVE",
                "error_message": "Payload conforms to current schema contract (re-validation passed)",
                "payload": inner_payload,
                "can_auto_heal": True,
            }

        first_err = errors[0]
        validator_rule = first_err.validator

        if validator_rule == "additionalProperties":
            return {
                "error_type": "SCHEMA_DRIFT",
                "error_message": f"Disallowed extra property detected: {first_err.message}",
                "field": list(first_err.path),
                "payload": inner_payload,
                "can_auto_heal": False,
            }

        if validator_rule in ("minimum", "maximum", "type", "required"):
            return {
                "error_type": "CONSTRAINT_VIOLATION",
                "error_message": f"Contract assertion violated: {first_err.message}",
                "field": list(first_err.path),
                "payload": inner_payload,
                "can_auto_heal": False,
            }

        return {
            "error_type": "SCHEMA_VIOLATION",
            "error_message": first_err.message,
            "field": list(first_err.path),
            "payload": inner_payload,
            "can_auto_heal": False,
        }

    def triage_batch(self, records: list[dict[str, Any] | str]) -> dict[str, Any]:
        """Triage and cluster a batch of quarantined records."""
        clustered: dict[str, list[dict[str, Any]]] = {
            "MALFORMED_JSON": [],
            "CONSTRAINT_VIOLATION": [],
            "SCHEMA_DRIFT": [],
            "UNREGISTERED_SCHEMA": [],
            "FALSE_POSITIVE": [],
            "SCHEMA_VIOLATION": [],
        }

        for rec in records:
            classified = self.classify_error(rec)
            err_type = classified["error_type"]
            clustered.setdefault(err_type, []).append(classified)

        total = len(records)
        healable = len(clustered.get("FALSE_POSITIVE", []))

        return {
            "total_quarantined": total,
            "auto_healable_count": healable,
            "signature_summary": {k: len(v) for k, v in clustered.items() if v},
            "clusters": clustered,
        }

    def simulate_replay(self, records: list[dict[str, Any] | str]) -> dict[str, Any]:
        """Dry-run simulation of replaying quarantined events back to active topic."""
        triage = self.triage_batch(records)
        ready_for_replay = triage["clusters"].get("FALSE_POSITIVE", [])

        return {
            "mode": "DRY_RUN",
            "total_examined": triage["total_quarantined"],
            "eligible_for_replay": len(ready_for_replay),
            "rejected_from_replay": triage["total_quarantined"] - len(ready_for_replay),
            "replayed_payloads": [item["payload"] for item in ready_for_replay],
            "quarantine_reasons": triage["signature_summary"],
        }


def main() -> None:
    """CLI entrypoint for DLQ Triage Engine."""
    parser = argparse.ArgumentParser(description="DLQ Incident Triage & Self-Healing Replay Engine")
    parser.add_argument("--input", required=True, help="Path to quarantined JSON file (or directory)")
    parser.add_argument("--dry-run", action="store_true", default=True, help="Simulate replay without side effects")
    args = parser.parse_args()

    engine = DLQTriageEngine()

    input_path = Path(args.input)
    if not input_path.exists():
        print(f"[ERROR] Input file not found: {args.input}", file=sys.stderr)
        sys.exit(1)

    records: list[Any] = []
    if input_path.is_file():
        with open(input_path, "r", encoding="utf-8") as f:
            content = json.load(f)
            records = content if isinstance(content, list) else [content]

    report = engine.simulate_replay(records)
    print(json.dumps(report, indent=2))
    print(f"\n[DLQ_TRIAGE] Examined {report['total_examined']} events. Eligible for replay: {report['eligible_for_replay']}.")


if __name__ == "__main__":
    main()
