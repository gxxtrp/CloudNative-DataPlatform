output "cluster" {
  description = "Managed Kafka cluster identity for runtime configuration."
  value       = google_managed_kafka_cluster.delivery.name
}

output "topics" {
  description = "Event topics with publisher-only Kafka ACLs."
  value       = sort([for topic in google_managed_kafka_topic.events : topic.topic_id])
}
