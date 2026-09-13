project_id                 = "sbx-workload-poc-508107"
region                     = "asia-southeast1"
name                       = "platform-dev-gke"
node_locations             = ["asia-southeast1-a"]
network_id                 = <%= output('foundation.network_id') %>
subnetwork_id              = <%= output('foundation.subnetwork_id') %>
pod_range_name             = <%= output('foundation.pod_range_name') %>
service_range_name         = <%= output('foundation.service_range_name') %>
node_service_account_email = <%= output('foundation.node_service_account_email') %>
master_ipv4_cidr_block     = "172.16.0.0/28"
core_machine_type          = "e2-standard-4"
core_min_nodes             = 1
core_max_nodes             = 2
compute_machine_type       = "e2-standard-4"
compute_min_nodes          = 0
compute_max_nodes          = 2
disk_size_gb               = 50
deletion_protection        = false
