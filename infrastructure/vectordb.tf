# Pinecone Index Configuration
resource "aws_ssm_parameter" "pinecone_config" {
  name  = "/docuvector/pinecone/config"
  type  = "SecureString"
  value = jsonencode({
    api_key      = var.pinecone_api_key
    environment  = var.pinecone_environment
    index_name   = "docuvector-index"
    dimension    = 1536
    metric       = "cosine"
    pods         = 1
    replicas     = 1
    pod_type     = "p1.x1"
  })
}

# Vector Database Scaling Policy
resource "aws_appautoscaling_policy" "vectordb_scaling" {
  name               = "docuvector-vectordb-scaling"
  service_namespace  = "custom"
  resource_id        = "index/docuvector-index"
  scalable_dimension = "custom:VectorDBIndexCapacity"
  policy_type        = "TargetTrackingScaling"

  target_tracking_scaling_policy_configuration {
    target_value = 70.0
    scale_in_cooldown  = 300
    scale_out_cooldown = 300

    customized_metric_specification {
      metric_name = "QueryLatency"
      namespace   = "Custom/DocuVector"
      statistic   = "Average"
      unit        = "Milliseconds"

      dimensions {
        name  = "IndexName"
        value = "docuvector-index"
      }
    }
  }
}

# Vector Database Monitoring
resource "aws_cloudwatch_metric_alarm" "vectordb_performance" {
  alarm_name          = "docuvector-vectordb-performance"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "QueryLatency"
  namespace           = "Custom/DocuVector"
  period             = "300"
  statistic          = "Average"
  threshold          = "1000"
  alarm_description  = "This metric monitors VectorDB query performance"

  dimensions = {
    IndexName = "docuvector-index"
  }
}

# Vector Database Backup Configuration
resource "aws_backup_plan" "vectordb_backup" {
  name = "docuvector-vectordb-backup"

  rule {
    rule_name         = "vectordb-daily-backup"
    target_vault_name = aws_backup_vault.vectordb.name
    schedule          = "cron(0 12 * * ? *)"

    lifecycle {
      delete_after = 30
    }
  }
}

resource "aws_backup_vault" "vectordb" {
  name = "docuvector-vectordb-backup-vault"
}

# Vector Database Security
resource "aws_security_group" "vectordb" {
  name        = "docuvector-vectordb-sg"
  description = "Security group for VectorDB access"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 443
    to_port     = 443
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

# Vector Database IAM Role
resource "aws_iam_role" "vectordb" {
  name = "docuvector-vectordb-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "vectordb" {
  name = "docuvector-vectordb-policy"
  role = aws_iam_role.vectordb.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters"
        ]
        Resource = aws_ssm_parameter.pinecone_config.arn
      }
    ]
  })
} 