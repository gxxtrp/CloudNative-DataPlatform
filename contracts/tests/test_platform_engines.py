"""Automated tests for Data Platform production engines:

1. Lakehouse Compactor (small-file bin-packing, Snappy compression, record integrity, cleanup)
2. Daily Financial Settlement (reconciliation math, VAT/commission, zero-tolerance quality gates)
3. DLQ Self-Healing & Safe Replay (error signature classification, dry-run simulation)
4. Stream Ingestion (Schema validation, Parquet micro-batches, DLQ quarantine)
"""

from __future__ import annotations

import json
from pathlib import Path

import duckdb
import pytest

from tools.compactor import LakehouseCompactor
from tools.dlq_triage import DLQTriageEngine
from tools.settlement import FinancialSettlementEngine, SettlementQualityGateError
from tools.stream_ingestor import LakehouseStreamIngestor

# ==============================================================================
# 1. Lakehouse Compactor Tests
# ==============================================================================

def test_compactor_binpacking_and_cleanup(tmp_path: Path) -> None:
    """Verify that compactor consolidates multiple micro-batch Parquet files and removes fragments."""
    source_dir = tmp_path / "bronze" / "orders"
    source_dir.mkdir(parents=True, exist_ok=True)
    target_dir = tmp_path / "silver" / "orders"
    target_dir.mkdir(parents=True, exist_ok=True)

    con = duckdb.connect(database=":memory:")

    # Generate 4 small fragmented micro-batch Parquet files (10 records each)
    total_records = 0
    for i in range(4):
        rows = [
            {"order_id": f"ord-{i}-{j}", "amount": float((j + 1) * 100), "status": "DELIVERED"}
            for j in range(10)
        ]
        total_records += len(rows)
        file_path = source_dir / f"part-00{i}.parquet"
        tmp_json = source_dir / f"tmp_{i}.json"
        tmp_json.write_text(json.dumps(rows), encoding="utf-8")
        con.execute(f"COPY (SELECT * FROM read_json_auto('{tmp_json.as_posix()}')) TO '{file_path.as_posix()}' (FORMAT PARQUET);")
        tmp_json.unlink()

    # Verify 4 source files exist
    assert len(list(source_dir.glob("*.parquet"))) == 4

    compactor = LakehouseCompactor(
        source_dir=str(source_dir),
        target_dir=str(target_dir),
        target_file_size_mb=64.0,
    )

    output_file = str(target_dir / "compacted-001.snappy.parquet")
    result = compactor.compact(str(source_dir / "*.parquet"), output_file)

    assert result["status"] == "SUCCESS"
    assert result["input_files"] == 4
    assert result["records_compacted"] == total_records
    assert Path(output_file).exists()

    # Verify compacted file has all 40 records
    compacted_count = con.execute(f"SELECT COUNT(*) FROM read_parquet('{Path(output_file).as_posix()}')").fetchone()[0]
    assert compacted_count == total_records

    # Verify source fragmented files were pruned
    assert len(list(source_dir.glob("*.parquet"))) == 0


def test_compactor_dry_run_does_not_modify(tmp_path: Path) -> None:
    """Verify that compactor dry-run inspects without writing output or deleting sources."""
    source_dir = tmp_path / "bronze"
    source_dir.mkdir(parents=True, exist_ok=True)
    con = duckdb.connect(database=":memory:")

    file_path = source_dir / "micro.parquet"
    tmp_json = source_dir / "tmp_dry.json"
    tmp_json.write_text(json.dumps([{"id": 1, "val": "test"}]), encoding="utf-8")
    con.execute(f"COPY (SELECT * FROM read_json_auto('{tmp_json.as_posix()}')) TO '{file_path.as_posix()}' (FORMAT PARQUET);")
    tmp_json.unlink()

    compactor = LakehouseCompactor(str(source_dir), str(tmp_path / "silver"))
    result = compactor.compact(str(source_dir / "*.parquet"), str(tmp_path / "silver" / "out.parquet"), dry_run=True)

    assert result["status"] == "DRY_RUN"
    assert result["input_files"] == 1
    assert result["records_to_compact"] == 1
    assert file_path.exists()
    assert not (tmp_path / "silver" / "out.parquet").exists()


# ==============================================================================
# 2. Financial Settlement & Quality Gate Tests
# ==============================================================================

def test_settlement_reconciliation_math_and_quality_gate(tmp_path: Path) -> None:
    """Verify two-sided financial reconciliation math, commission (30%), VAT (7%), and gold mart export."""
    input_file = tmp_path / "bronze_orders.parquet"
    gold_file = tmp_path / "gold" / "merchant_payout.parquet"

    # Dataset:
    # merch-a: 2 delivered orders (500 + 300 = 800 gross)
    #   Commission = 800 * 0.30 = 240.00
    #   VAT = 240 * 0.07 = 16.80
    #   Net = 800 - 240 - 16.80 = 543.20
    # merch-b: 1 delivered order (1000 gross) + 1 cancelled order (400 gross, should be ignored)
    #   Commission = 1000 * 0.30 = 300.00
    #   VAT = 300 * 0.07 = 21.00
    #   Net = 1000 - 300 - 21.00 = 679.00
    test_orders = [
        {"order_id": "ord-1", "customer_id": "c1", "merchant_id": "merch-a", "amount": 500.0, "status": "DELIVERED"},
        {"order_id": "ord-2", "customer_id": "c2", "merchant_id": "merch-a", "amount": 300.0, "status": "DELIVERED"},
        {"order_id": "ord-3", "customer_id": "c3", "merchant_id": "merch-b", "amount": 1000.0, "status": "DELIVERED"},
        {"order_id": "ord-4", "customer_id": "c4", "merchant_id": "merch-b", "amount": 400.0, "status": "CANCELLED"},
    ]

    con = duckdb.connect(database=":memory:")
    tmp_json = tmp_path / "temp_orders.json"
    tmp_json.write_text(json.dumps(test_orders), encoding="utf-8")
    con.execute(f"COPY (SELECT * FROM read_json_auto('{tmp_json.as_posix()}')) TO '{input_file.as_posix()}' (FORMAT PARQUET);")
    tmp_json.unlink()

    engine = FinancialSettlementEngine()
    brief = engine.run_settlement(str(input_file), str(gold_file), settlement_date="2026-09-07")

    assert brief["quality_gate_status"] == "PASSED"
    assert brief["total_merchants"] == 2
    assert brief["total_orders_settled"] == 3
    assert brief["total_orphaned_orders"] == 1
    assert brief["total_gross_gmv"] == 1800.00
    assert brief["total_commission"] == 540.00
    assert brief["total_vat"] == 37.80
    assert brief["total_net_payout"] == 1222.20
    assert brief["negative_payout_errors"] == 0
    assert brief["ledger_discrepancy_cents"] == 0.0
    assert Path(gold_file).exists()

    # Verify Gold Parquet readable and schema matches
    gold_rows = con.execute(
        f"SELECT merchant_id, net_payout FROM read_parquet('{Path(gold_file).as_posix()}') ORDER BY merchant_id"
    ).fetchall()
    assert len(gold_rows) == 2
    assert gold_rows[0][0] == "merch-a"
    assert gold_rows[0][1] == 543.20
    assert gold_rows[1][0] == "merch-b"
    assert gold_rows[1][1] == 679.00


def test_settlement_quality_gate_rejects_negative_payout(tmp_path: Path) -> None:
    """Verify zero-tolerance quality gate halts job and raises SettlementQualityGateError on negative payout."""
    input_file = tmp_path / "negative_orders.parquet"
    gold_file = tmp_path / "gold_fail.parquet"

    bad_orders = [
        {"order_id": "ord-bad", "customer_id": "c1", "merchant_id": "merch-err", "amount": -100.0, "status": "DELIVERED"},
    ]
    con = duckdb.connect(database=":memory:")
    tmp_json = tmp_path / "temp_bad.json"
    tmp_json.write_text(json.dumps(bad_orders), encoding="utf-8")
    con.execute(f"COPY (SELECT * FROM read_json_auto('{tmp_json.as_posix()}')) TO '{input_file.as_posix()}' (FORMAT PARQUET);")
    tmp_json.unlink()

    engine = FinancialSettlementEngine()
    with pytest.raises(SettlementQualityGateError) as excinfo:
        engine.run_settlement(str(input_file), str(gold_file), settlement_date="2026-09-07")

    assert "negative net payouts" in str(excinfo.value)
    assert not Path(gold_file).exists()


# ==============================================================================
# 3. DLQ Incident Triage & Safe Replay Tests
# ==============================================================================

def test_dlq_triage_error_classification() -> None:
    """Verify error signature clustering: CONSTRAINT_VIOLATION, SCHEMA_DRIFT, MALFORMED_JSON, FALSE_POSITIVE."""
    engine = DLQTriageEngine()

    base_valid_order = {
        "event_id": "11111111-2222-3333-4444-555555555555",
        "event_timestamp": "2026-09-07T01:00:00Z",
        "order_id": "ORD-BKK-001",
        "order_status": "CREATED",
        "merchant_id": "MCH-001",
        "customer_id": "CUST-001",
        "total_amount_baht": 250.0,
        "payment_method": "PROMPTPAY",
    }

    # 1. Constraint violation: negative amount
    rec_constraint = dict(base_valid_order, total_amount_baht=-50.0)
    c1 = engine.classify_error(rec_constraint)
    assert c1["error_type"] == "CONSTRAINT_VIOLATION"
    assert c1["can_auto_heal"] is False

    # 2. Schema drift: unregistered additional property
    rec_drift = dict(base_valid_order, unregistered_internal_debug_flag=True)
    c2 = engine.classify_error(rec_drift)
    assert c2["error_type"] == "SCHEMA_DRIFT"

    # 3. Malformed JSON string
    c3 = engine.classify_error("{ bad json broken: ")
    assert c3["error_type"] == "MALFORMED_JSON"

    # 4. Valid order (False positive / remediated)
    c4 = engine.classify_error(base_valid_order)
    assert c4["error_type"] == "FALSE_POSITIVE"
    assert c4["can_auto_heal"] is True


def test_dlq_simulate_replay_dry_run() -> None:
    """Verify DLQ dry-run simulation separates healable payloads from rejected records."""
    engine = DLQTriageEngine()

    valid_order = {
        "event_id": "11111111-2222-3333-4444-555555555555",
        "event_timestamp": "2026-09-07T01:00:00Z",
        "order_id": "ORD-BKK-001",
        "order_status": "CREATED",
        "merchant_id": "MCH-001",
        "customer_id": "CUST-001",
        "total_amount_baht": 100.0,
        "payment_method": "PROMPTPAY",
    }

    bad_order = dict(valid_order, total_amount_baht=-99.0)

    records = [
        valid_order,
        bad_order,
        "{ broken: json",
    ]

    report = engine.simulate_replay(records)
    assert report["mode"] == "DRY_RUN"
    assert report["total_examined"] == 3
    assert report["eligible_for_replay"] == 1
    assert report["rejected_from_replay"] == 2
    assert len(report["replayed_payloads"]) == 1
    assert report["replayed_payloads"][0]["order_id"] == "ORD-BKK-001"


# ==============================================================================
# 4. Stream Ingestion to Lakehouse Tests
# ==============================================================================

def test_stream_ingestor_snappy_parquet_and_quarantine(tmp_path: Path) -> None:
    """Verify that stream ingestor partitions valid events to Snappy Parquet and routes invalid events to DLQ."""
    bronze_dir = tmp_path / "lakehouse-bronze"
    quarantine_dir = tmp_path / "lakehouse-quarantine"

    ingestor = LakehouseStreamIngestor(
        bronze_base_path=bronze_dir,
        quarantine_base_path=quarantine_dir,
    )

    batch = [
        {
            "event_id": "11111111-2222-3333-4444-555555555555",
            "event_timestamp": "2026-09-07T01:00:00Z",
            "order_id": "ORD-BKK-001",
            "order_status": "CREATED",
            "merchant_id": "MCH-001",
            "customer_id": "CUST-001",
            "total_amount_baht": 420.0,
            "payment_method": "PROMPTPAY",
        },
        {
            "event_id": "22222222-2222-3333-4444-555555555555",
            "event_timestamp": "2026-09-07T01:00:00Z",
            "order_id": "ORD-POISON",
            "order_status": "CREATED",
            "merchant_id": "MCH-001",
            "customer_id": "CUST-001",
            "total_amount_baht": -500.0,  # Violates minimum >= 0
            "payment_method": "PROMPTPAY",
        },
    ]

    res = ingestor.process_events(batch, event_type="order", batch_id="unit_test")

    assert res["total_received"] == 2
    assert res["valid_count"] == 1
    assert res["dlq_count"] == 1
    assert res["parquet_written"] is not None
    assert res["dlq_written"] is not None

    # Verify Parquet file was written and can be read by DuckDB
    con = duckdb.connect(database=":memory:")
    written_rows = con.execute(f"SELECT * FROM read_parquet('{Path(res['parquet_written']).as_posix()}')").fetchall()
    assert len(written_rows) == 1

    # Verify DLQ JSON quarantine file contains quarantine envelope
    with open(res["dlq_written"], "r", encoding="utf-8") as f:
        quarantine_data = json.load(f)
    assert len(quarantine_data) == 1
    assert "Contract violation" in quarantine_data[0]["error_reason"]
    assert quarantine_data[0]["raw_payload"]["order_id"] == "ORD-POISON"
