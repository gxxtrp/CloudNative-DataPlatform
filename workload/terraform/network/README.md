# Workload Private Network Terraform

This root creates the private VPC seam used by the two publisher modules. It has no public IP, Cloud NAT, or public load balancer.

- `workload-run` is attached to Cloud Run through Direct VPC egress.
- Private Google Access keeps Google control-plane traffic on Google infrastructure.
- Managed Kafka later creates Private Service Connect endpoints in this subnet; the Data Platform project receives only the narrow service-agent permission required to do that.

Apply this root after `../foundation` and before `../cloud-sql` or the Data Platform Managed Kafka root.
