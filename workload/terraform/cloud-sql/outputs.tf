output "instance_connection_name" {
  description = "Cloud SQL connection name for the publisher database adapter."
  value       = google_sql_database_instance.workload.connection_name
}

output "private_ip_address" {
  description = "Private-only address reachable from the Workload VPC."
  value       = google_sql_database_instance.workload.private_ip_address
}

output "database_name" {
  description = "Operational database that stores Orders, Rider telemetry, and the transactional outbox."
  value       = google_sql_database.workload.name
}

output "publisher_service_accounts" {
  description = "Runtime identities used by Cloud Run, Cloud SQL IAM authentication, and Kafka ACLs."
  value = {
    for key, service_account in google_service_account.publisher : key => service_account.email
  }
}

output "publisher_database_users" {
  description = "Cloud SQL IAM database usernames for the publisher adapters."
  value = {
    for key, service_account in google_service_account.publisher : key => trimsuffix(service_account.email, ".gserviceaccount.com")
  }
}
