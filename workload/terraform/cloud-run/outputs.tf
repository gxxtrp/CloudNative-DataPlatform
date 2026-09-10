output "publisher_uris" {
  description = "Cloud Run URLs; ingress policy restricts them to internal callers."
  value = {
    for key, publisher in google_cloud_run_v2_service.publisher : key => publisher.uri
  }
}
