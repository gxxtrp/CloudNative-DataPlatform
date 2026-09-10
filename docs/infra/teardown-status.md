# GCP teardown status

Status recorded: 2026-09-10.

## Deleted

- Managed Kafka cluster `delivery-poc`, its topics, ACLs, service identity, and cross-project IAM grants.
- Cloud SQL instance `workload-postgres`, database, IAM database users, publisher service accounts, and Cloud SQL IAM grants.
- Data Platform buckets: `raw`, `quarantine`, `checkpoints`, and `artifacts`.
- BigQuery datasets: `delivery_staging`, `delivery_curated`, and `delivery_operations`.
- Workload subnet `workload-run` (`10.20.0.0/24`).
- GitHub Actions workload identity federation, Terraform plan service accounts, and their IAM bindings.

Cloud Run services and the Artifact Registry repository were never created.

## Pending teardown

The following resources remain because Google retains the Cloud SQL service-producer resources for up to four days after deleting a private-IP Cloud SQL instance:

- VPC `workload-private` in `workload-508107`.
- Private Services Access connection `servicenetworking-googleapis-com` on that VPC.
- Reserved Private Services Access range `workload-private-services` (`10.7.0.0/16`).

Terraform currently tracks these resources:

```text
workload/terraform/cloud-sql
  google_compute_global_address.private_services
  google_service_networking_connection.private_services

workload/terraform/network
  google_compute_network.workload
```

After Google releases the producer resources, finish the teardown in this order:

```sh
terraform -chdir=workload/terraform/cloud-sql destroy
terraform -chdir=workload/terraform/network destroy
```

Do not run a normal `terraform apply` from the previous Cloud SQL or network roots before redesigning them: those configurations still describe the old instance and subnet.

## Kept

- GCP projects `workload-508107` and `dataplatform-508107`.
- Terraform state buckets `gs://workload-508107-tf-state` and `gs://dataplatform-508107-tf-state`.
- The global billing cap and project billing configuration.
- Default VPC networks created by GCP.
- Enabled Google APIs. The foundation roots used `disable_on_destroy = false`, so destroying those Terraform resources removed them from state without disabling the APIs.

The remaining VPC and Private Services Access connection can be reused for a redesigned platform before the four-day window ends.
