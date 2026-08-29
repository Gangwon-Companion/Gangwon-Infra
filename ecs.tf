locals {
  name = "${var.project_name}-${var.environment}"

  ecr_lifecycle_policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep the latest 10 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = { type = "expire" }
    }]
  })
}

resource "aws_cloudwatch_log_group" "be" {
  name              = "/ecs/${local.name}/be"
  retention_in_days = 14
}

resource "aws_cloudwatch_log_group" "ai" {
  name              = "/ecs/${local.name}/ai"
  retention_in_days = 14
}

resource "aws_ecs_cluster" "main" {
  name = local.name
}

resource "aws_ecs_task_definition" "app" {
  family                   = "${local.name}-app"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "1024"
  memory                   = "2048"
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  lifecycle {
    create_before_destroy = true
  }

  container_definitions = jsonencode([
    {
      name      = "be"
      image     = "${aws_ecr_repository.be.repository_url}:${var.be_image_tag}"
      essential = true
      cpu       = 512
      memory    = 1024
      portMappings = [{
        containerPort = 8080
        hostPort      = 8080
        protocol      = "tcp"
      }]
      environment = [
        { name = "SPRING_PROFILES_ACTIVE", value = "prod" },
        { name = "SPRING_DATASOURCE_URL", value = "jdbc:postgresql://${aws_db_instance.main.address}:5432/${var.db_name}" },
        { name = "SPRING_DATASOURCE_USERNAME", value = var.db_username },
        { name = "SEARCH_ENGINE", value = "rdb" },
        { name = "AWS_REGION", value = var.aws_region },
        { name = "AWS_S3_BUCKET", value = aws_s3_bucket.community.id },
        { name = "CAPTCHA_ENABLED", value = "false" },
        { name = "AI_SERVER_URL", value = "http://localhost:8000" },
        { name = "CORS_ALLOWED_ORIGIN_PATTERNS", value = var.cors_allowed_origin_patterns },
        { name = "SPRING_JPA_HIBERNATE_DDL_AUTO", value = var.spring_jpa_ddl_auto }
      ]
      secrets = [
        { name = "SPRING_DATASOURCE_PASSWORD", valueFrom = "${aws_db_instance.main.master_user_secret[0].secret_arn}:password::" },
        { name = "JWT_SECRET", valueFrom = "${aws_secretsmanager_secret.app.arn}:JWT_SECRET::" },
        { name = "PERSONAL_DATA_ENCRYPTION_KEY", valueFrom = "${aws_secretsmanager_secret.app.arn}:PERSONAL_DATA_ENCRYPTION_KEY::" },
        { name = "TOUR_API_KEY", valueFrom = "${aws_secretsmanager_secret.app.arn}:TOUR_API_KEY::" }
      ]
      healthCheck = {
        command     = ["CMD-SHELL", "wget -q -O /dev/null http://localhost:8080/actuator/health || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 60
      }
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.be.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "ecs"
        }
      }
    },
    {
      name      = "ai"
      image     = "${aws_ecr_repository.ai.repository_url}:${var.ai_image_tag}"
      essential = true
      cpu       = 512
      memory    = 768
      portMappings = [{
        containerPort = 8000
        hostPort      = 8000
        protocol      = "tcp"
      }]
      environment = [
        { name = "GANGWON_BE_BASE_URL", value = "http://localhost:8080" },
        { name = "GANGWON_RESPONSE_LLM_ENABLED", value = tostring(var.ai_response_llm_enabled) },
        { name = "GANGWON_RESPONSE_LLM_MODEL", value = var.ai_response_llm_model },
        { name = "OPENAI_BASE_URL", value = var.openai_base_url }
      ]
      secrets = var.ai_response_llm_enabled ? [
        { name = "OPENAI_API_KEY", valueFrom = "${aws_secretsmanager_secret.app.arn}:OPENAI_API_KEY::" }
      ] : []
      healthCheck = {
        command     = ["CMD", "python", "-c", "import urllib.request; urllib.request.urlopen('http://localhost:8000/health', timeout=3)"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 15
      }
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.ai.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])
}

resource "aws_ecs_service" "app" {
  name            = "${local.name}-app"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = var.ecs_desired_count
  launch_type     = "FARGATE"

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  network_configuration {
    subnets          = aws_subnet.public[*].id
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.be.arn
    container_name   = "be"
    container_port   = 8080
  }

  depends_on = [aws_lb_listener.http, aws_lb_listener.http_redirect]

  lifecycle {
    ignore_changes = [task_definition, desired_count]
  }
}
