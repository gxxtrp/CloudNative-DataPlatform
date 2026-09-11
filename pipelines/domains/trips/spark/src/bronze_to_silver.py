"""
Bronze to Silver transformation for Trips domain.

This Spark job:
1. Reads CDC events from Bronze layer (Iceberg)
2. Deduplicates by taking latest CDC event per trip_id
3. Applies schema enforcement and type casting
4. Writes to Silver layer (Iceberg) with MERGE upsert
"""

import argparse
from datetime import datetime
from pyspark.sql import SparkSession
from pyspark.sql import functions as F
from pyspark.sql.window import Window


def create_spark_session(app_name: str) -> SparkSession:
    """Create Spark session with Iceberg configurations."""
    return (
        SparkSession.builder
        .appName(app_name)
        .config("spark.sql.extensions", "org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions")
        .config("spark.sql.catalog.iceberg", "org.apache.iceberg.spark.SparkCatalog")
        .config("spark.sql.catalog.iceberg.type", "hadoop")
        .getOrCreate()
    )


def read_bronze_trips(spark: SparkSession, lake_bucket: str, process_date: str):
    """Read raw CDC events from Bronze layer."""
    bronze_path = f"gs://{lake_bucket}/bronze/cdc/trips"
    
    df = (
        spark.read
        .format("iceberg")
        .load(bronze_path)
        .filter(F.col("_date") == process_date)
    )
    
    return df


def transform_trips(df):
    """
    Transform Bronze trips to Silver format.
    
    - Parse CDC payload
    - Deduplicate (keep latest per trip_id)
    - Type cast and null handling
    - Add derived columns
    """
    # Parse CDC payload (assuming JSON)
    parsed_df = df.select(
        F.get_json_object(F.col("value"), "$.after.trip_id").alias("trip_id"),
        F.get_json_object(F.col("value"), "$.after.rider_id").alias("rider_id"),
        F.get_json_object(F.col("value"), "$.after.driver_id").alias("driver_id"),
        F.get_json_object(F.col("value"), "$.after.status").alias("status"),
        F.get_json_object(F.col("value"), "$.after.pickup_lat").cast("double").alias("pickup_lat"),
        F.get_json_object(F.col("value"), "$.after.pickup_lng").cast("double").alias("pickup_lng"),
        F.get_json_object(F.col("value"), "$.after.dropoff_lat").cast("double").alias("dropoff_lat"),
        F.get_json_object(F.col("value"), "$.after.dropoff_lng").cast("double").alias("dropoff_lng"),
        F.get_json_object(F.col("value"), "$.after.city_id").cast("int").alias("city_id"),
        F.to_timestamp(F.get_json_object(F.col("value"), "$.after.requested_at")).alias("requested_at"),
        F.to_timestamp(F.get_json_object(F.col("value"), "$.after.matched_at")).alias("matched_at"),
        F.to_timestamp(F.get_json_object(F.col("value"), "$.after.started_at")).alias("started_at"),
        F.to_timestamp(F.get_json_object(F.col("value"), "$.after.completed_at")).alias("completed_at"),
        F.to_timestamp(F.get_json_object(F.col("value"), "$.after.cancelled_at")).alias("cancelled_at"),
        F.get_json_object(F.col("value"), "$.after.fare_cents").cast("int").alias("fare_cents"),
        F.get_json_object(F.col("value"), "$.after.surge_multiplier").cast("decimal(3,2)").alias("surge_multiplier"),
        F.get_json_object(F.col("value"), "$.after.distance_meters").cast("int").alias("distance_meters"),
        F.get_json_object(F.col("value"), "$.after.duration_seconds").cast("int").alias("duration_seconds"),
        F.get_json_object(F.col("value"), "$.op").alias("_cdc_operation"),
        F.get_json_object(F.col("value"), "$.ts_ms").cast("long").alias("_cdc_timestamp_ms"),
        F.col("_ingested_at")
    )
    
    # Deduplicate: keep latest CDC event per trip_id
    window = Window.partitionBy("trip_id").orderBy(F.desc("_cdc_timestamp_ms"))
    deduped_df = (
        parsed_df
        .withColumn("_rn", F.row_number().over(window))
        .filter(F.col("_rn") == 1)
        .drop("_rn")
    )
    
    # Derived columns
    final_df = (
        deduped_df
        .withColumn("fare_usd", F.col("fare_cents") / 100.0)
        .withColumn("distance_miles", F.col("distance_meters") / 1609.34)
        .withColumn("duration_minutes", F.col("duration_seconds") / 60.0)
        .withColumn("event_date", F.to_date("requested_at"))
        .withColumn("_processed_at", F.current_timestamp())
        .drop("fare_cents", "distance_meters", "duration_seconds")
    )
    
    return final_df


def write_silver_trips(df, spark: SparkSession, lake_bucket: str):
    """Write to Silver layer using MERGE (upsert)."""
    silver_path = f"gs://{lake_bucket}/silver/trips"
    
    # Register source as temp view
    df.createOrReplaceTempView("source_trips")
    
    # MERGE into Silver table
    spark.sql(f"""
        MERGE INTO iceberg.`{silver_path}` AS target
        USING source_trips AS source
        ON target.trip_id = source.trip_id
        WHEN MATCHED THEN
            UPDATE SET *
        WHEN NOT MATCHED THEN
            INSERT *
    """)


def main():
    parser = argparse.ArgumentParser(description="Bronze to Silver: Trips")
    parser.add_argument("--date", required=True, help="Processing date (YYYY-MM-DD)")
    parser.add_argument("--lake-bucket", default="dataplatform-dev-lake", help="GCS bucket for data lake")
    args = parser.parse_args()
    
    spark = create_spark_session("trips-bronze-to-silver")
    
    try:
        print(f"Processing trips for date: {args.date}")
        
        # Read Bronze
        bronze_df = read_bronze_trips(spark, args.lake_bucket, args.date)
        bronze_count = bronze_df.count()
        print(f"Read {bronze_count} records from Bronze")
        
        # Transform
        silver_df = transform_trips(bronze_df)
        
        # Write Silver
        write_silver_trips(silver_df, spark, args.lake_bucket)
        print(f"Successfully wrote to Silver layer")
        
    finally:
        spark.stop()


if __name__ == "__main__":
    main()
