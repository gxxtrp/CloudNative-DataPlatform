# Managed Kafka Terraform

This root creates the billed Managed Service for Apache Kafka runtime in `dataplatform` and connects it directly to the `workload-run` subnet in the separate Workload project. It does not use Shared VPC or VPC peering.

Before apply:

1. Apply `workload/terraform/network` so `workload-run` exists.
2. Confirm the existing Data Platform foundation has enabled `managedkafka.googleapis.com`.
3. Review the selected vCPU and memory sizing. Managed Kafka is continuously billed even when topics are idle.

The cluster service agent is given `roles/managedkafka.serviceAgent` only in the Workload project, which lets it create the required Private Service Connect endpoints and DNS records in that one connected subnet. Topic ACLs grant the future Order and Rider Cloud Run identities `WRITE` only.
