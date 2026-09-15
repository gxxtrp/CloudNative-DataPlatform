"""Publish a landed NYC Yellow Taxi Parquet batch to an Iceberg bronze table."""

from __future__ import annotations

import argparse
import json
import os
from datetime import datetime, timezone
from typing import Mapping


EXPECTED_SCHEMA = {
    "VendorID": "int",
    "tpep_pickup_datetime": "timestamp",
    "tpep_dropoff_datetime": "timestamp",
    "passenger_count": "bigint",
    "trip_distance": "double",
    "RatecodeID": "bigint",
    "store_and_fwd_flag": "string",
    "PULocationID": "int",
    "DOLocationID": "int",
    "payment_type": "bigint",
    "fare_amount": "double",
    "extra": "double",
    "mta_tax": "double",
    "tip_amount": "double",
    "tolls_amount": "double",
    "improvement_surcharge": "double",
    "total_amount": "double",
    "congestion_surcharge": "double",
    "Airport_fee": "double",
}


def format_month(month: str | int) -> str:
    value = int(month)
    if value < 1 or value > 12:
        raise ValueError(f"month must be between 1 and 12, got {month}")
    return f"{value:02d}"


def schema_mismatches(actual: Mapping[str, str]) -> list[str]:
    """Return deterministic source-schema differences for quarantine reporting."""
    failures = []
    for name, expected_type in EXPECTED_SCHEMA.items():
        actual_type = actual.get(name)
        if actual_type is None:
            failures.append(f"missing column: {name}")
        elif actual_type != expected_type:
            failures.append(f"{name}: expected {expected_type}, got {actual_type}")
    return failures


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-uri", required=True)
    parser.add_argument("--source-sha256", required=True)
    parser.add_argument("--year", required=True, type=int)
    parser.add_argument("--month", required=True)
    parser.add_argument("--table", default="polaris.bronze.nyc_yellow_taxi")
    return parser.parse_args()


def create_spark_session():
    from pyspark.sql import SparkSession

    credential = os.environ["POLARIS_CREDENTIAL"]
    return (
        SparkSession.builder.appName("nyc-yellow-taxi-bronze-publisher")
        .config(
            "spark.sql.extensions",
            "org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions",
        )
        .config("spark.sql.catalog.polaris", "org.apache.iceberg.spark.SparkCatalog")
        .config("spark.sql.catalog.polaris.type", "rest")
        .config(
            "spark.sql.catalog.polaris.uri",
            "http://polaris.catalog.svc.cluster.local:8181/api/catalog",
        )
        .config(
            "spark.sql.catalog.polaris.oauth2-server-uri",
            "http://polaris.catalog.svc.cluster.local:8181/api/catalog/v1/oauth/tokens",
        )
        .config("spark.sql.catalog.polaris.warehouse", "polaris-lakehouse")
        .config("spark.sql.catalog.polaris.scope", "PRINCIPAL_ROLE:ALL")
        .config("spark.sql.catalog.polaris.credential", credential)
        .config("spark.sql.catalog.polaris.token-refresh-enabled", "true")
        .config("spark.redaction.regex", "(?i)secret|password|token|access[.]?key|credential")
        .getOrCreate()
    )


def publish() -> None:
    from pyspark.sql import functions

    args = parse_args()
    month = format_month(args.month)
    spark = create_spark_session()

    try:
        source = spark.read.parquet(args.source_uri)
        actual_schema = {field.name: field.dataType.simpleString() for field in source.schema.fields}
        failures = schema_mismatches(actual_schema)
        if failures:
            raise ValueError("source schema rejected: " + "; ".join(failures))

        row_count = source.count()
        if row_count == 0:
            raise ValueError("source batch contains no rows")

        null_key_count = source.filter(
            functions.col("tpep_pickup_datetime").isNull()
            | functions.col("tpep_dropoff_datetime").isNull()
            | functions.col("PULocationID").isNull()
            | functions.col("DOLocationID").isNull()
        ).count()
        if null_key_count:
            raise ValueError(f"source batch contains {null_key_count} rows with null required fields")

        published_at = datetime.now(timezone.utc).isoformat()
        bronze = (
            source.withColumn("_source_file", functions.input_file_name())
            .withColumn("_source_sha256", functions.lit(args.source_sha256))
            .withColumn("_batch_year", functions.lit(args.year))
            .withColumn("_batch_month", functions.lit(int(month)))
            .withColumn("_published_at_utc", functions.lit(published_at).cast("timestamp"))
        )

        spark.sql("CREATE NAMESPACE IF NOT EXISTS polaris.bronze")
        if spark.catalog.tableExists(args.table):
            bronze.writeTo(args.table).overwritePartitions()
        else:
            (
                bronze.writeTo(args.table)
                .using("iceberg")
                .partitionedBy("_batch_year", "_batch_month")
                .tableProperty("format-version", "2")
                .create()
            )

        published_count = spark.table(args.table).filter(
            (functions.col("_batch_year") == args.year)
            & (functions.col("_batch_month") == int(month))
        ).count()
        if published_count != row_count:
            raise RuntimeError(
                f"publication count mismatch: source={row_count}, bronze={published_count}"
            )

        print(
            json.dumps(
                {
                    "status": "published",
                    "source_uri": args.source_uri,
                    "source_sha256": args.source_sha256,
                    "table": args.table,
                    "year": args.year,
                    "month": month,
                    "row_count": row_count,
                    "published_at_utc": published_at,
                },
                sort_keys=True,
            )
        )
    finally:
        spark.stop()


if __name__ == "__main__":
    publish()
