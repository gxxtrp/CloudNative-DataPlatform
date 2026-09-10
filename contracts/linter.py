#!/usr/bin/env python3
"""
Cloud-Native Data Platform - Data Contract Linter & Compatibility Gatekeeper
Validates JSON Schemas and enforces backward-compatibility rules in CI/CD.
"""

import json
import re
import sys
from collections import defaultdict
from pathlib import Path
from typing import Any

import jsonschema

SEMVER_PATTERN = re.compile(r"^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$")

if sys.stdout and hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")
if sys.stderr and hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8")


def load_json(path: Path) -> dict[str, Any]:
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def validate_meta_schema(schema_path: Path, schema: dict[str, Any]) -> list[str]:
    errors = []
    # 1. Validate schema syntax
    try:
        jsonschema.Draft7Validator.check_schema(schema)
    except jsonschema.exceptions.SchemaError as e:
        errors.append(f"Invalid JSON Schema syntax: {e.message}")

    # 2. Enforce Data Contract metadata requirements
    metadata = schema.get("metadata")
    if not metadata or not isinstance(metadata, dict):
        errors.append("Missing required top-level 'metadata' object.")
    else:
        for required_key in ["domain", "owner_team", "version", "sla_freshness_seconds"]:
            if required_key not in metadata:
                errors.append(f"Missing required metadata field: '{required_key}'.")
        version = metadata.get("version")
        if not isinstance(version, str) or not SEMVER_PATTERN.fullmatch(version):
            errors.append("Metadata field 'version' must use MAJOR.MINOR.PATCH semantic versioning.")

    # 3. Require title and type
    if not schema.get("title"):
        errors.append("Missing required 'title' attribute.")
    if schema.get("type") != "object":
        errors.append("Top-level contract schema type must be 'object'.")

    return errors


def check_backward_compatibility(
    old_schema: dict[str, Any], new_schema: dict[str, Any]
) -> list[str]:
    """
    Enforce backward-compatibility rules:
    - No deleted properties
    - No changed property types
    - No new required fields without defaults
    """
    breaking_changes = []

    old_props = old_schema.get("properties", {})
    new_props = new_schema.get("properties", {})

    old_required = set(old_schema.get("required", []))
    new_required = set(new_schema.get("required", []))

    # 1. Check for deleted properties
    for prop_name, prop_spec in old_props.items():
        if prop_name not in new_props:
            breaking_changes.append(
                f"BREAKING: Property '{prop_name}' was removed from contract."
            )
        else:
            # 2. Check for altered types
            old_type = prop_spec.get("type")
            new_type = new_props[prop_name].get("type")
            if old_type != new_type:
                breaking_changes.append(
                    f"BREAKING: Property '{prop_name}' type changed from '{old_type}' to '{new_type}'."
                )

    # 3. Check for newly added required fields
    newly_added_required = new_required - old_required
    for prop_name in newly_added_required:
        prop_def = new_props.get(prop_name, {})
        if "default" not in prop_def:
            breaking_changes.append(
                f"BREAKING: Newly added required property '{prop_name}' lacks a default value."
            )

    return breaking_changes


def semantic_version(schema: dict[str, Any]) -> tuple[int, int, int]:
    """Return a validated contract semantic version for version-aware checks."""
    version = schema["metadata"]["version"]
    match = SEMVER_PATTERN.fullmatch(version)
    if match is None:
        raise ValueError(f"Invalid semantic version: {version}")
    return tuple(int(part) for part in match.groups())


def schema_family(schema_path: Path) -> str:
    """Group `orders.lifecycle.v1.json` and later versions into one contract family."""
    family_name = re.sub(r"\.v\d+\.json$", "", schema_path.name)
    return str(schema_path.parent / family_name)


def check_versioned_compatibility(
    old_schema: dict[str, Any], new_schema: dict[str, Any]
) -> list[str]:
    """Require a major version increase when a contract intentionally breaks callers."""
    breaking_changes = check_backward_compatibility(old_schema, new_schema)
    if not breaking_changes:
        return []

    old_major, _, _ = semantic_version(old_schema)
    new_major, _, _ = semantic_version(new_schema)
    if new_major > old_major:
        return []

    return [
        "BREAKING: Contract compatibility changed without a major version increase."
    ] + breaking_changes


def main() -> int:
    print("========================================================================")
    print("  Cloud-Native Data Platform: Contract Compatibility Linter")
    print("========================================================================")

    # Find schemas directory relative to root or contracts/
    contracts_dir = Path("contracts/schemas")
    if not contracts_dir.exists():
        contracts_dir = Path(__file__).parent / "schemas"

    schema_files = list(contracts_dir.glob("**/*.json"))

    if not schema_files:
        print(f"❌ No JSON schema files found under {contracts_dir}")
        return 1

    total_errors = 0
    valid_schemas: dict[Path, dict[str, Any]] = {}

    for schema_file in sorted(schema_files):
        print(f"\n[SCAN] Checking {schema_file.as_posix()}...")
        try:
            schema_data = load_json(schema_file)
            errors = validate_meta_schema(schema_file, schema_data)
            if errors:
                for err in errors:
                    print(f"  ❌ {err}")
                total_errors += len(errors)
            else:
                title = schema_data.get("title")
                ver = schema_data.get("metadata", {}).get("version")
                owner = schema_data.get("metadata", {}).get("owner_team")
                print(f"  ✅ Valid Contract: {title} (v{ver}) - Owner: {owner}")
                valid_schemas[schema_file] = schema_data
        except (json.JSONDecodeError, OSError) as e:
            print(f"  ❌ Failed to parse JSON: {e}")
            total_errors += 1

    print("\n[COMPATIBILITY] Checking versioned contract families...")
    families: dict[str, list[Path]] = defaultdict(list)
    for schema_file in valid_schemas:
        families[schema_family(schema_file)].append(schema_file)

    for family, family_files in sorted(families.items()):
        ordered_files = sorted(family_files, key=lambda path: semantic_version(valid_schemas[path]))
        for old_file, new_file in zip(ordered_files, ordered_files[1:]):
            compatibility_errors = check_versioned_compatibility(
                valid_schemas[old_file], valid_schemas[new_file]
            )
            if compatibility_errors:
                print(f"  ❌ {family}: {old_file.name} -> {new_file.name}")
                for error in compatibility_errors:
                    print(f"     {error}")
                total_errors += len(compatibility_errors)
            else:
                print(f"  ✅ {family}: {old_file.name} -> {new_file.name}")

    # Simulated Mutation Test: Verify breaking change detection
    print("\n[SELF-TEST] Testing backward-compatibility gatekeeper logic...")
    sample = load_json(schema_files[0])
    mutated = json.loads(json.dumps(sample))
    if mutated.get("properties"):
        del_key = next(iter(mutated["properties"].keys()))
        del mutated["properties"][del_key]
        breaks = check_backward_compatibility(sample, mutated)
        assert len(breaks) > 0, "Compatibility checker failed to catch deleted field!"
        print("  ✅ Backward compatibility detector successfully caught simulated breaking mutation.")

    print("\n------------------------------------------------------------------------")
    if total_errors == 0:
        print("🎉 ALL DATA CONTRACTS PASSED VALIDATION (0 errors).")
        return 0
    else:
        print(f"❌ LINTER FAILED: {total_errors} errors detected across contracts.")
        return 1


if __name__ == "__main__":
    sys.exit(main())
