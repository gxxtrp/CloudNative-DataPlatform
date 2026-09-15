# NYC Yellow Taxi bronze publisher

This Spark workload reads one retained NYC Yellow Taxi Parquet batch, validates
its source schema and required fields, and atomically replaces the matching
year/month partition in `polaris.bronze.nyc_yellow_taxi`.

The source URI and checksum in `application.yaml` match the first successful
2024-01 landing. Re-running the application replaces that Iceberg partition
instead of appending duplicate rows.

The Spark driver reads the `polaris-client` Secret from the `processing`
namespace. Create it with `scripts/apply-secrets.sh`; do not commit the client
secret.
