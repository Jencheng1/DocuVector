# CloudWatch Dashboard
resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "docuvector-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/ECS", "CPUUtilization", "ClusterName", "docuvector-cluster"],
            ["AWS/ECS", "MemoryUtilization", "ClusterName", "docuvector-cluster"]
          ]
          period = 300
          stat   = "Average"
          region = var.aws_region
          title  = "ECS Cluster Metrics"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["Custom/DocuVector", "DocumentProcessingTime", "Service", "docuvector"],
            ["Custom/DocuVector", "VectorDBQueryTime", "Service", "docuvector"]
          ]
          period = 300
          stat   = "Average"
          region = var.aws_region
          title  = "Processing Performance"
        }
      }
    ]
  })
}

# Predictive Scaling Policy
resource "aws_appautoscaling_policy" "predictive" {
  name               = "docuvector-predictive-scaling"
  service_namespace  = "ecs"
  resource_id        = "service/${aws_ecs_cluster.main.name}/${aws_ecs_service.app.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  policy_type        = "PredictiveScaling"

  predictive_scaling_configuration {
    mode               = "ForecastAndScale"
    scheduling_buffer_time = 300
    max_capacity_behavior = "SetForecastCapacityToMax"
    max_capacity_buffer  = 10
  }
}

# Anomaly Detection
resource "aws_cloudwatch_metric_alarm" "processing_anomaly" {
  alarm_name          = "docuvector-processing-anomaly"
  comparison_operator = "GreaterThanUpperThreshold"
  evaluation_periods  = "2"
  threshold_metric_id = "e1"
  alarm_description   = "This metric monitors for anomalous document processing times"

  metric_query {
    id          = "e1"
    expression  = "ANOMALY_DETECTION_BAND(m1, 2)"
    label       = "Processing Time (Expected)"
    return_data = "true"
  }

  metric_query {
    id          = "m1"
    metric {
      metric_name = "DocumentProcessingTime"
      namespace   = "Custom/DocuVector"
      period      = "300"
      stat        = "Average"
      unit        = "Seconds"
    }
  }
}

# Operational Metrics
resource "aws_cloudwatch_metric_alarm" "operational_health" {
  alarm_name          = "docuvector-operational-health"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "3"
  metric_name         = "HealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period             = "60"
  statistic          = "Average"
  threshold          = "1"
  alarm_description  = "This metric monitors the operational health of the service"
}

# Log Insights Query
resource "aws_cloudwatch_log_metric_filter" "error_patterns" {
  name           = "docuvector-error-patterns"
  pattern        = "ERROR"
  log_group_name = aws_cloudwatch_log_group.app.name

  metric_transformation {
    name      = "ErrorCount"
    namespace = "Custom/DocuVector"
    value     = "1"
  }
}

# EventBridge Rules for Automation
resource "aws_cloudwatch_event_rule" "auto_remediation" {
  name        = "docuvector-auto-remediation"
  description = "Trigger automated remediation for common issues"

  event_pattern = jsonencode({
    source      = ["aws.ecs"]
    detail-type = ["ECS Task State Change"]
    detail = {
      lastStatus = ["STOPPED"]
      stoppedReason = ["*"]
    }
  })
}

resource "aws_cloudwatch_event_target" "remediation_lambda" {
  rule      = aws_cloudwatch_event_rule.auto_remediation.name
  target_id = "RemediationLambda"
  arn       = aws_lambda_function.remediation.arn
} 