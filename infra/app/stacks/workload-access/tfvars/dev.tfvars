project_id                 = "sbx-workload-poc-508107"
region                     = "asia-southeast1"
node_service_account_email = <%= output('foundation.node_service_account_email') %>
bucket_name                = <%= output('data-services.bucket_name') %>
lake_buckets               = <%= output('data-services.buckets') %>
repository_id              = <%= output('data-services.repository_id') %>
workload_sa_name           = "platform-dev-workload"
workload_namespace         = "platform"
workload_ksa_name          = "platform-workload"
