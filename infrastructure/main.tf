terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# VPC Configuration
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "docuvector-vpc"
  }
}

# Subnets
resource "aws_subnet" "public" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.${count.index + 1}.0/24"
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name = "public-subnet-${count.index + 1}"
  }
}

# S3 Bucket for Document Storage
resource "aws_s3_bucket" "documents" {
  bucket = "docuvector-documents-${var.environment}"
  
  tags = {
    Name        = "docuvector-documents"
    Environment = var.environment
  }
}

# Lambda Function for Document Processing
resource "aws_lambda_function" "processor" {
  filename         = "lambda_function.zip"
  function_name    = "docuvector-processor"
  role             = aws_iam_role.lambda_role.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.9"
  timeout          = 300
  memory_size      = 1024

  environment {
    variables = {
      PINECONE_API_KEY      = var.pinecone_api_key
      PINECONE_ENVIRONMENT  = var.pinecone_environment
      S3_BUCKET            = aws_s3_bucket.documents.id
    }
  }
}

# SageMaker Endpoint
resource "aws_sagemaker_endpoint" "model" {
  name                 = "docuvector-model-endpoint"
  endpoint_config_name = aws_sagemaker_endpoint_configuration.model.name
}

resource "aws_sagemaker_endpoint_configuration" "model" {
  name = "docuvector-model-config"

  production_variants {
    variant_name           = "variant-1"
    model_name            = aws_sagemaker_model.model.name
    initial_instance_count = 1
    instance_type         = "ml.t2.medium"
  }
}

# MLflow Tracking Server
resource "aws_ecs_task_definition" "mlflow" {
  family                   = "docuvector-mlflow"
  network_mode            = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                     = 256
  memory                  = 512

  container_definitions = jsonencode([
    {
      name      = "mlflow"
      image     = "mlflow/mlflow:latest"
      essential = true
      portMappings = [
        {
          containerPort = 5000
          hostPort      = 5000
          protocol      = "tcp"
        }
      ]
      environment = [
        {
          name  = "MLFLOW_TRACKING_URI"
          value = "sqlite:///mlflow.db"
        }
      ]
    }
  ])
}

# AIOps Components
resource "aws_cloudwatch_metric_alarm" "anomaly_detection" {
  alarm_name          = "docuvector-anomaly-detection"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "AnomalyScore"
  namespace           = "Custom/DocuVector"
  period             = "300"
  statistic          = "Average"
  threshold          = "0.8"
  alarm_description  = "This metric monitors for anomalous behavior in document processing"
}

# ECS Cluster
resource "aws_ecs_cluster" "main" {
  name = "docuvector-cluster"
}

# ECS Task Definition
resource "aws_ecs_task_definition" "app" {
  family                   = "docuvector"
  network_mode            = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                     = 256
  memory                  = 512

  container_definitions = jsonencode([
    {
      name      = "docuvector"
      image     = "${aws_ecr_repository.app.repository_url}:latest"
      essential = true
      portMappings = [
        {
          containerPort = 8000
          hostPort      = 8000
          protocol      = "tcp"
        }
      ]
      environment = [
        {
          name  = "PINECONE_API_KEY"
          value = var.pinecone_api_key
        },
        {
          name  = "PINECONE_ENVIRONMENT"
          value = var.pinecone_environment
        },
        {
          name  = "MLFLOW_TRACKING_URI"
          value = "http://${aws_ecs_service.mlflow.name}:5000"
        },
        {
          name  = "SAGEMAKER_ENDPOINT"
          value = aws_sagemaker_endpoint.model.name
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.app.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])
}

# ECR Repository
resource "aws_ecr_repository" "app" {
  name = "docuvector"
}

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "app" {
  name              = "/ecs/docuvector"
  retention_in_days = 30
}

# Security Group
resource "aws_security_group" "ecs_tasks" {
  name        = "docuvector-sg"
  description = "Security group for ECS tasks"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 8000
    to_port     = 8000
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

# Variables
variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "pinecone_api_key" {
  description = "Pinecone API key"
  type        = string
  sensitive   = true
}

variable "pinecone_environment" {
  description = "Pinecone environment"
  type        = string
}

variable "environment" {
  description = "Environment name (e.g., dev, prod)"
  type        = string
  default     = "dev"
}

# Data sources
data "aws_availability_zones" "available" {
  state = "available"
}

# IAM Role for Lambda
resource "aws_iam_role" "lambda_role" {
  name = "docuvector-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

# Outputs
output "ecs_cluster_name" {
  value = aws_ecs_cluster.main.name
}

output "ecr_repository_url" {
  value = aws_ecr_repository.app.repository_url
}

output "s3_bucket_name" {
  value = aws_s3_bucket.documents.id
}

output "sagemaker_endpoint" {
  value = aws_sagemaker_endpoint.model.name
}

output "mlflow_tracking_uri" {
  value = "http://${aws_ecs_service.mlflow.name}:5000"
} 