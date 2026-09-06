terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.40.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "data-platform"
      Environment = "free_tier_aws"
      CostCenter  = "zero-cost-portfolio"
      ManagedBy   = "terraform"
    }
  }
}

# ------------------------------------------------------------------------------
# 1. AWS S3 Lakehouse Buckets (3-Tier Medallion + Quarantine)
# Fits 100% in AWS Free Tier (5GB storage, 20,000 GET, 2,000 PUT requests/month)
# ------------------------------------------------------------------------------
locals {
  lakehouse_buckets = [
    "${var.project_prefix}-bronze-lakehouse",
    "${var.project_prefix}-silver-lakehouse",
    "${var.project_prefix}-gold-lakehouse",
    "${var.project_prefix}-quarantine",
  ]
}

resource "aws_s3_bucket" "lakehouse" {
  for_each = toset(local.lakehouse_buckets)
  bucket   = each.key

  force_destroy = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "lakehouse" {
  for_each = aws_s3_bucket.lakehouse
  bucket   = each.value.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "lakehouse" {
  for_each = aws_s3_bucket.lakehouse
  bucket   = each.value.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ------------------------------------------------------------------------------
# 2. Cloud FinOps: AWS S3 Gateway VPC Endpoint ($0.00 Data Transfer Fee)
# Bypasses NAT Gateways so Petabyte Lakehouse reads/writes avoid $0.045/GB fees!
# ------------------------------------------------------------------------------
resource "aws_vpc" "data_platform" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.project_prefix}-vpc"
  }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.data_platform.id

  tags = {
    Name = "${var.project_prefix}-private-rt"
  }
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id          = aws_vpc.data_platform.id
  service_name    = "com.amazonaws.${var.aws_region}.s3"
  route_table_ids = [aws_route_table.private.id]

  tags = {
    Name = "${var.project_prefix}-s3-gateway-endpoint"
  }
}

# ------------------------------------------------------------------------------
# 3. AWS IAM Roles for Service Accounts (IRSA) for Flink & Spark
# ------------------------------------------------------------------------------
data "aws_iam_policy_document" "s3_lakehouse_access" {
  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket",
    ]
    resources = [
      for b in aws_s3_bucket.lakehouse : "${b.arn}/*"
    ]
  }

  statement {
    effect = "Allow"
    actions = [
      "s3:ListBucket",
      "s3:GetBucketLocation",
    ]
    resources = [
      for b in aws_s3_bucket.lakehouse : b.arn
    ]
  }
}

resource "aws_iam_policy" "lakehouse_rw" {
  name        = "${var.project_prefix}-lakehouse-policy"
  description = "Read/Write policy for Apache Iceberg Lakehouse on S3"
  policy      = data.aws_iam_policy_document.s3_lakehouse_access.json
}
