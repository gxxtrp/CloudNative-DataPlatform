# Workload Cloud SQL Terraform

This root owns the publishers' private PostgreSQL instance, operational database, and two IAM-authenticated runtime identities.

Set `terraform_operator_email` to the Google account that runs `terraform apply`. Terraform authenticates that account with ADC and uses the Cloud SQL Data API for the idempotent schema bootstrap; no database password or service-account key is stored.

- Cloud SQL has private IP only; `ipv4_enabled` is false.
- The app identities use `cloudsql.client` and `cloudsql.instanceUser`; no service-account key or application database password exists.
- Backups and seven days of point-in-time recovery are enabled. Deletion is prevented by default.
- `db-f1-micro` and `ZONAL` are deliberate POC defaults. They are not covered by the Cloud SQL SLA. Set `database_tier` and `availability_type = "REGIONAL"` before a production deployment.

Apply `../network` first. The `servicenetworking.googleapis.com` API is enabled by `../foundation` and is required for private services access.
