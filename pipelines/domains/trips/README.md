# Trips Domain Pipelines

This directory contains data pipelines for the Trips domain.

## Owner

**Team:** Trips Domain Team  
**Slack:** #team-trips  
**On-call:** trips-oncall@company.com

## Pipelines

### Spark Jobs

| Job | Description | Schedule |
|-----|-------------|----------|
| `bronze_to_silver.py` | CDC deduplication, type casting | Daily 2 AM |

### Flink Jobs

| Job | Description | Type |
|-----|-------------|------|
| `TripStreamingJob` | Real-time trip events processing | Long-running |

### DBT Models

| Model | Layer | Description |
|-------|-------|-------------|
| `stg_trips` | Silver | Staging view on Iceberg |
| `fact_trips` | Gold | Trip fact table |
| `agg_city_daily` | Gold | Daily city aggregations |

## Local Development

### Spark

```bash
cd spark
pip install -e ".[dev]"
pytest tests/
```

### Flink

```bash
cd flink
mvn clean verify
```

### DBT

```bash
cd ../../../dbt
dbt run --select tag:trips
dbt test --select tag:trips
```

## Deployment

Pipelines are deployed automatically via GitHub Actions when changes are pushed to `main`.

Manual deployment:
```bash
# Submit Spark job
argo submit ../../orchestration/workflows/trips/daily-etl.yaml \
  -p execution-date=$(date +%Y-%m-%d)
```

## Monitoring

- **Argo UI:** https://argo.dataplatform.internal
- **Grafana:** https://grafana.dataplatform.internal/d/trips-pipelines
- **OpenMetadata:** https://openmetadata.dataplatform.internal/table/trips
