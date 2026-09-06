output "s3_buckets" {
  description = "Created AWS Free Tier S3 lakehouse buckets"
  value       = [for b in aws_s3_bucket.lakehouse : b.id]
}

output "s3_gateway_vpc_endpoint_id" {
  description = "AWS S3 Gateway VPC Endpoint ID ($0.00 data transfer fee)"
  value       = aws_vpc_endpoint.s3.id
}

output "iam_lakehouse_policy_arn" {
  description = "IAM policy ARN for Iceberg read/write"
  value       = aws_iam_policy.lakehouse_rw.arn
}
