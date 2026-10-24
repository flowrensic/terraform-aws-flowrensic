resource "aws_ecs_cluster" "this" {
  name = var.name
}

resource "aws_ecs_task_definition" "server" {
  family                   = var.name
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "ARM64"
  }

  container_definitions = jsonencode(concat([{
    name      = "server"
    image     = "${var.image}:${var.image_version}"
    essential = true
    portMappings = [
      { containerPort = local.main_port, protocol = "tcp" },
      { containerPort = local.ingest_port, protocol = "tcp" },
    ]
    environment = [
      { name = "FLOWRENSIC_ADDR", value = ":${local.main_port}" },
      { name = "FLOWRENSIC_INGEST_ADDR", value = ":${local.ingest_port}" },
      { name = "FLOWRENSIC_UI_BASE_URL", value = "https://${var.ui_name}" },
      { name = "FLOWRENSIC_DATABASE_URL", value = "postgres://${aws_db_instance.this.username}@${aws_db_instance.this.address}:${aws_db_instance.this.port}/${aws_db_instance.this.db_name}?sslmode=require" },
      { name = "FLOWRENSIC_BLOB_BACKEND", value = "s3" },
      { name = "FLOWRENSIC_BLOB_S3_BUCKET", value = aws_s3_bucket.histories.id },
      { name = "FLOWRENSIC_BLOB_S3_REGION", value = var.region },
      { name = "FLOWRENSIC_BLOB_S3_ENDPOINT", value = "s3.${var.region}.amazonaws.com" },
    ]
    secrets = concat(
      [
        { name = "FLOWRENSIC_ENVS", valueFrom = local.envs_parameter_arn },
        { name = "PGPASSWORD", valueFrom = "${aws_db_instance.this.master_user_secret[0].secret_arn}:password::" },
      ],
      [for variable, arn in local.secret_parameter_arns : { name = variable, valueFrom = arn }],
    )
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.server.name
        awslogs-region        = var.region
        awslogs-stream-prefix = "server"
      }
    }
  }], slice([local.agent_container], 0, local.monitoring_cloud)))
}

# One server at a time: an update stops the old task before it starts the new one.
resource "aws_ecs_service" "server" {
  name                               = var.name
  cluster                            = aws_ecs_cluster.this.id
  task_definition                    = aws_ecs_task_definition.server.arn
  launch_type                        = "FARGATE"
  desired_count                      = 1
  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 100
  health_check_grace_period_seconds  = 60
  wait_for_steady_state              = true

  network_configuration {
    subnets          = var.public_subnet_ids
    security_groups  = [aws_security_group.server.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.ui_public.arn
    container_name   = "server"
    container_port   = local.main_port
  }

  dynamic "load_balancer" {
    for_each = aws_lb_target_group.ui_internal
    content {
      target_group_arn = load_balancer.value.arn
      container_name   = "server"
      container_port   = local.main_port
    }
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.ingest.arn
    container_name   = "server"
    container_port   = local.ingest_port
  }

  dynamic "service_registries" {
    for_each = aws_service_discovery_service.server
    content {
      registry_arn = service_registries.value.arn
    }
  }

  depends_on = [
    aws_lb_listener.ui_public,
    aws_lb_listener.ui_internal,
    aws_lb_listener.ingest,
    aws_iam_role_policy.execution_secrets,
    aws_iam_role_policy.task,
    aws_s3_bucket_policy.histories,
    aws_vpc_endpoint.s3,
  ]
}
