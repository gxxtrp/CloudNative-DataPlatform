project_id                 = "sbx-workload-poc-508107"
region                     = "asia-southeast1"
node_service_account_email = <%= output('foundation.node_service_account_email') %>
bucket_name                = <%= output('data-services.bucket_name') %>
lake_buckets               = <%= output('data-services.buckets') %>
repository_id              = <%= output('data-services.repository_id') %>
workload_sa_name           = "platform-dev-workload"
workload_namespace         = "platform"
workload_ksa_name          = "platform-workload"

workload_identity_bindings = [
  { namespace = "platform", ksa_name = "platform-workload" },
  { namespace = "argo", ksa_name = "argo" },
  { namespace = "argo", ksa_name = "argo-server" },
  { namespace = "argo", ksa_name = "workflow-controller" },
  { namespace = "catalog", ksa_name = "polaris" },
  { namespace = "ingestion", ksa_name = "ingestion-runner" },
  { namespace = "processing", ksa_name = "processing-runner" }
]
