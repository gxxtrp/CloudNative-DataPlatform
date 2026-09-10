# Private Publisher Cloud Run Terraform

This root deploys the Order and Rider publisher modules only after the following interfaces exist:

1. `../network` supplies the Direct VPC egress subnet.
2. `../cloud-sql` supplies the Cloud SQL private address, connection name, database name, and runtime identities through its remote-state outputs.
3. `../artifact-registry` has an immutable image for each publisher.
4. `dataplatform/terraform/managed-kafka` is active and its private bootstrap address is supplied in `terraform.tfvars`.

Both modules have internal-only ingress, no unauthenticated invoker binding, and `PRIVATE_RANGES_ONLY` Direct VPC egress. Their Cloud SQL identity is injected through the Cloud SQL root's output rather than copied into local configuration. The current publisher implementation must be migrated to its IAM-authenticated Cloud SQL outbox adapter before applying this root.
