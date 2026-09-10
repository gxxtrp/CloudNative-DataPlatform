# Managed Data Terraform

This root creates the durable, managed storage and analytics foundation for the Data Platform project. It is intentionally separate from `foundation` state and creates no Kubernetes cluster, Kafka cluster, data, secret values, or public endpoint.

## Resources

- Four regional, private Cloud Storage buckets: raw, quarantine, checkpoints, and artifacts.
- Three empty regional BigQuery datasets: `delivery_staging`, `delivery_curated`, and `delivery_operations`.
- Versioning and lifecycle deletion for synthetic POC data. The lifecycle rule controls object cleanup; it does not lock a bucket or permit Terraform to destroy it.

## Apply

1. Apply `../foundation` first; it enables the Storage and BigQuery APIs.
2. Copy `terraform.tfvars.example` to ignored `terraform.tfvars`, entering `dataplatform-508107` and `asia-southeast1`.
3. Run `terraform init`, review `terraform plan`, then apply with your administrator identity.

After apply, find the buckets in **Cloud Storage** and the datasets in **BigQuery Studio**. The module creates empty destinations only; publishing synthetic records is a later processor milestone.
