# Security Hub Integration
resource "aws_securityhub_account" "main" {
  enable_default_standards = true
}

# GuardDuty Configuration
resource "aws_guardduty_detector" "main" {
  enable = true
}

# AWS Config Rules
resource "aws_config_configuration_recorder" "main" {
  name     = "docuvector-config-recorder"
  role_arn = aws_iam_role.config.arn
}

resource "aws_config_delivery_channel" "main" {
  name           = "docuvector-delivery-channel"
  s3_bucket_name = aws_s3_bucket.config.bucket
  depends_on     = [aws_config_configuration_recorder.main]
}

# KMS Key for Encryption
resource "aws_kms_key" "main" {
  description             = "KMS key for DocuVector encryption"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = "*"
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "kms:CallerAccount" = var.aws_account_id
          }
        }
      }
    ]
  })
}

# WAF Configuration
resource "aws_wafv2_web_acl" "main" {
  name        = "docuvector-waf"
  scope       = "REGIONAL"
  description = "WAF for DocuVector application"

  default_action {
    allow {}
  }

  rule {
    name     = "AWS-AWSManagedRulesCommonRuleSet"
    priority = 1

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWS-AWSManagedRulesCommonRuleSet"
      sampled_requests_enabled   = true
    }
  }
}

# IAM Roles and Policies
resource "aws_iam_role" "config" {
  name = "docuvector-config-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "config.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "config" {
  role       = aws_iam_role.config.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSConfigRole"
}

# CloudTrail Configuration
resource "aws_cloudtrail" "main" {
  name                          = "docuvector-trail"
  s3_bucket_name               = aws_s3_bucket.cloudtrail.bucket
  include_global_service_events = true
  is_multi_region_trail        = true
  enable_logging               = true

  event_selector {
    read_write_type           = "All"
    include_management_events = true
  }
}

# S3 Buckets for Security Logs
resource "aws_s3_bucket" "config" {
  bucket = "docuvector-config-logs"
  acl    = "private"
}

resource "aws_s3_bucket" "cloudtrail" {
  bucket = "docuvector-cloudtrail-logs"
  acl    = "private"
}

# S3 Bucket Policies
resource "aws_s3_bucket_policy" "config" {
  bucket = aws_s3_bucket.config.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "config.amazonaws.com"
        }
        Action = [
          "s3:PutObject"
        ]
        Resource = "${aws_s3_bucket.config.arn}/*"
      }
    ]
  })
}

resource "aws_s3_bucket_policy" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action = [
          "s3:PutObject"
        ]
        Resource = "${aws_s3_bucket.cloudtrail.arn}/*"
      }
    ]
  })
}

# VPC Flow Logs
resource "aws_flow_log" "main" {
  log_destination      = aws_s3_bucket.flow_logs.arn
  log_destination_type = "s3"
  traffic_type         = "ALL"
  vpc_id              = aws_vpc.main.id
}

resource "aws_s3_bucket" "flow_logs" {
  bucket = "docuvector-flow-logs"
  acl    = "private"
}

# Security Groups
resource "aws_security_group" "bastion" {
  name        = "docuvector-bastion-sg"
  description = "Security group for bastion host"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Network ACLs
resource "aws_network_acl" "main" {
  vpc_id = aws_vpc.main.id

  egress {
    protocol   = "-1"
    rule_no    = 200
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }

  ingress {
    protocol   = "-1"
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }
} 