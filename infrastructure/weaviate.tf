# Weaviate Infrastructure Configuration

# Weaviate ECS Task Definition
resource "aws_ecs_task_definition" "weaviate" {
  family                   = "weaviate"
  network_mode            = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                     = 4096
  memory                  = 8192
  execution_role_arn      = aws_iam_role.ecs_execution_role.arn
  task_role_arn          = aws_iam_role.weaviate_task_role.arn

  container_definitions = jsonencode([
    {
      name  = "weaviate"
      image = "semitechnologies/weaviate:1.19.0"
      portMappings = [
        {
          containerPort = 8080
          hostPort      = 8080
          protocol      = "tcp"
        }
      ]
      environment = [
        {
          name  = "AUTHENTICATION_ANONYMOUS_ACCESS_ENABLED"
          value = "true"
        },
        {
          name  = "PERSISTENCE_DATA_PATH"
          value = "/var/lib/weaviate"
        },
        {
          name  = "CLUSTER_HOSTNAME"
          value = "node1"
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = "/ecs/weaviate"
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }
      mountPoints = [
        {
          sourceVolume  = "weaviate-data"
          containerPath = "/var/lib/weaviate"
          readOnly     = false
        }
      ]
    }
  ])

  volume {
    name = "weaviate-data"
    efs_volume_configuration {
      file_system_id = aws_efs_file_system.weaviate.id
    }
  }
}

# Weaviate ECS Service
resource "aws_ecs_service" "weaviate" {
  name            = "weaviate"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.weaviate.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.private.*.id
    security_groups  = [aws_security_group.weaviate.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.weaviate.arn
    container_name   = "weaviate"
    container_port   = 8080
  }
}

# Weaviate Security Group
resource "aws_security_group" "weaviate" {
  name        = "weaviate-sg"
  description = "Security group for Weaviate"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Weaviate EFS File System
resource "aws_efs_file_system" "weaviate" {
  creation_token = "weaviate-data"
  encrypted      = true

  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
  }

  tags = {
    Name = "weaviate-data"
  }
}

# Weaviate EFS Mount Target
resource "aws_efs_mount_target" "weaviate" {
  count           = length(aws_subnet.private)
  file_system_id  = aws_efs_file_system.weaviate.id
  subnet_id       = aws_subnet.private[count.index].id
  security_groups = [aws_security_group.efs.id]
}

# Weaviate IAM Role
resource "aws_iam_role" "weaviate_task_role" {
  name = "weaviate-task-role"

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

# Weaviate IAM Policy
resource "aws_iam_role_policy" "weaviate" {
  name = "weaviate-policy"
  role = aws_iam_role.weaviate_task_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/ecs/weaviate:*"
      }
    ]
  })
}

# Weaviate CloudWatch Log Group
resource "aws_cloudwatch_log_group" "weaviate" {
  name              = "/ecs/weaviate"
  retention_in_days = 30
}

# Weaviate ALB Target Group
resource "aws_lb_target_group" "weaviate" {
  name        = "weaviate-tg"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  health_check {
    path                = "/v1/meta"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    matcher             = "200"
  }
}

# Weaviate ALB Listener Rule
resource "aws_lb_listener_rule" "weaviate" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.weaviate.arn
  }

  condition {
    host_header {
      values = ["weaviate.${var.domain_name}"]
    }
  }
} 