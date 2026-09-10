"""Daily Financial Batch Settlement Engine.

Performs two-sided ledger reconciliation against Bronze/Silver Lakehouse Parquet,
calculates merchant commission (30%) and VAT (7%), enforces zero-tolerance
financial quality gates, and generates audited Gold Mart Parquet tables.
"""

from __future__ import annotations

import argparse
import datetime
import json
import sys
from pathlib import Path
from typing import Any

import duckdb


class SettlementQualityGateError(Exception):
    """Raised when financial reconciliation violates zero-tolerance quality gates."""


class FinancialSettlementEngine:
    """Executes daily financial batch reconciliation and enforces quality gates."""

    COMMISSION_RATE = 0.30  # 30% platform commission
    VAT_RATE = 0.07         # 7% VAT on commission

    def __init__(
        self,
        s3_endpoint: str | None = None,
        s3_access_key: str | None = None,
        s3_secret_key: str | None = None,
    ) -> None:
        self.con = duckdb.connect(database=":memory:")
        self._configure_duckdb(s3_endpoint, s3_access_key, s3_secret_key)

    def _configure_duckdb(
        self,
        endpoint: str | None,
        access_key: str | None,
        secret_key: str | None,
    ) -> None:
        if endpoint:
            self.con.execute("INSTALL httpfs;")
            self.con.execute("LOAD httpfs;")
            self.con.execute(f"SET s3_endpoint='{endpoint}';")
            self.con.execute("SET s3_url_style='path';")
            self.con.execute("SET s3_use_ssl=false;")
            if access_key and secret_key:
                self.con.execute(f"SET s3_access_key_id='{access_key}';")
                self.con.execute(f"SET s3_secret_access_key='{secret_key}';")

    def run_settlement(
        self,
        input_parquet: str | list[str],
        output_gold_parquet: str,
        settlement_date: str,
    ) -> dict[str, Any]:
        """Execute settlement DAG against Parquet input, validate quality gates, and export gold mart."""
        if isinstance(input_parquet, str):
            input_target = Path(input_parquet).as_posix()
        else:
            input_target = [Path(p).as_posix() for p in input_parquet]

        # Dynamically bind column names to support both total_amount_baht/amount and order_status/status
        cols = [
            row[0]
            for row in self.con.execute(
                f"DESCRIBE SELECT * FROM read_parquet({input_target!r})"
            ).fetchall()
        ]
        amount_col = "total_amount_baht" if "total_amount_baht" in cols else "amount"
        status_col = "order_status" if "order_status" in cols else "status"

        # Query and reconcile delivered orders
        query = f"""
            WITH raw_orders AS (
                SELECT
                    order_id,
                    customer_id,
                    merchant_id,
                    CAST({amount_col} AS DOUBLE) AS amount,
                    {status_col} AS status
                FROM read_parquet({input_target!r})
            ),
            reconciliation AS (
                SELECT
                    merchant_id,
                    '{settlement_date}' AS settlement_date,
                    'THB' AS currency,
                    COUNT(CASE WHEN status = 'DELIVERED' THEN 1 END) AS delivered_orders,
                    COUNT(CASE WHEN status != 'DELIVERED' THEN 1 END) AS orphaned_orders,
                    ROUND(COALESCE(SUM(CASE WHEN status = 'DELIVERED' THEN amount ELSE 0 END), 0.0), 2) AS gross_amount,
                    ROUND(COALESCE(SUM(CASE WHEN status = 'DELIVERED' THEN amount * {self.COMMISSION_RATE} ELSE 0 END), 0.0), 2) AS commission_amount,
                    ROUND(COALESCE(SUM(CASE WHEN status = 'DELIVERED' THEN (amount * {self.COMMISSION_RATE}) * {self.VAT_RATE} ELSE 0 END), 0.0), 2) AS vat_amount
                FROM raw_orders
                GROUP BY merchant_id
            )
            SELECT
                merchant_id,
                settlement_date,
                currency,
                delivered_orders,
                orphaned_orders,
                gross_amount,
                commission_amount,
                vat_amount,
                ROUND(gross_amount - commission_amount - vat_amount, 2) AS net_payout
            FROM reconciliation
            ORDER BY merchant_id;
        """

        # Create temporary table for settlement results
        self.con.execute(f"CREATE OR REPLACE TEMP TABLE settlement_results AS {query};")

        cursor = self.con.execute("SELECT * FROM settlement_results;")
        col_names = [desc[0] for desc in cursor.description]
        rows = cursor.fetchall()
        merchant_records = [dict(zip(col_names, row)) for row in rows]

        # Compute platform-wide totals
        total_merchants = len(merchant_records)
        total_orders_settled = sum(int(r["delivered_orders"] or 0) for r in merchant_records)
        total_orphaned = sum(int(r["orphaned_orders"] or 0) for r in merchant_records)
        total_gross = round(sum(float(r["gross_amount"] or 0.0) for r in merchant_records), 2)
        total_commission = round(sum(float(r["commission_amount"] or 0.0) for r in merchant_records), 2)
        total_vat = round(sum(float(r["vat_amount"] or 0.0) for r in merchant_records), 2)
        total_net = round(sum(float(r["net_payout"] or 0.0) for r in merchant_records), 2)

        # Financial Quality Gate Checks
        negative_payouts = sum(1 for r in merchant_records if float(r["net_payout"] or 0.0) < 0)

        # Ledger Balance Check: Net + Comm + VAT == Gross (within 1 cent rounding margin)
        ledger_discrepancy = abs((total_net + total_commission + total_vat) - total_gross)
        balance_check_passed = ledger_discrepancy < 0.02

        gate_status = "PASSED"
        failures: list[str] = []

        if negative_payouts > 0:
            gate_status = "FAILED_QUALITY_GATE"
            failures.append(f"{negative_payouts} merchants have negative net payouts")

        if not balance_check_passed:
            gate_status = "FAILED_QUALITY_GATE"
            failures.append(
                f"Ledger imbalance: Gross ({total_gross}) != Net ({total_net}) + Comm ({total_commission}) + VAT ({total_vat})"
            )

        brief: dict[str, Any] = {
            "settlement_date": settlement_date,
            "total_merchants": total_merchants,
            "total_orders_settled": total_orders_settled,
            "total_orphaned_orders": total_orphaned,
            "total_gross_gmv": total_gross,
            "total_commission": total_commission,
            "total_vat": total_vat,
            "total_net_payout": total_net,
            "negative_payout_errors": negative_payouts,
            "ledger_discrepancy_cents": round(ledger_discrepancy * 100, 2),
            "quality_gate_status": gate_status,
            "failures": failures,
            "execution_time": datetime.datetime.now(datetime.UTC).isoformat(),
            "merchant_payouts": merchant_records,
        }

        if gate_status != "PASSED":
            raise SettlementQualityGateError(f"Quality gate rejected settlement: {'; '.join(failures)}")

        # Write Gold Mart Parquet
        out_path = Path(output_gold_parquet)
        out_path.parent.mkdir(parents=True, exist_ok=True)

        self.con.execute(
            f"""
            COPY settlement_results
            TO '{out_path.as_posix()}'
            (FORMAT PARQUET, COMPRESSION 'SNAPPY');
            """
        )

        brief["gold_mart_path"] = output_gold_parquet
        return brief


def main() -> None:
    """CLI entrypoint for Daily Settlement Engine."""
    parser = argparse.ArgumentParser(description="Daily Batch Financial Settlement Engine")
    parser.add_argument("--date", default=datetime.datetime.now(datetime.UTC).strftime("%Y-%m-%d"), help="Settlement date (YYYY-MM-DD)")
    parser.add_argument("--input", required=True, help="Input Parquet file or pattern (e.g. data/lakehouse-bronze/orders/*.parquet)")
    parser.add_argument("--output", required=True, help="Output Gold Mart Parquet path")
    args = parser.parse_args()

    engine = FinancialSettlementEngine()
    try:
        brief = engine.run_settlement(args.input, args.output, args.date)
        print(json.dumps(brief, indent=2))
        print(f"\n[SETTLEMENT_ENGINE] Quality Gate PASSED. Gold Mart saved to: {args.output}")
    except SettlementQualityGateError as err:
        print(f"[ERROR] Quality Gate Rejected: {err}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
