# The monitoring the setting monitoring picks. With ecs, Prometheus and Grafana
# run as one more ECS service in the cluster: Prometheus finds every server task
# through Cloud Map and keeps its data on EFS, and Grafana is at grafana. and
# ui_name behind the UI load balancers, the module's own or the user's. With grafana_cloud, a Prometheus in
# agent mode beside the server sends what it scrapes to Grafana Cloud, and the
# dashboards go into that Grafana. With none, nothing.

locals {
  monitoring_ecs   = var.monitoring == "ecs" ? 1 : 0
  monitoring_cloud = var.monitoring == "grafana_cloud" ? 1 : 0

  metrics_port = 9464
  grafana_port = 3000
  grafana_name = "grafana.${var.ui_name}"

  prometheus_image = "prom/prometheus:v3.5.0"
  grafana_image    = "grafana/grafana:13.0.1"

  # The dashboard files of deploy/grafana/dashboards, through the symlink dashboards, by the end of their uid.
  dashboards_dir = "${path.module}/dashboards"
  dashboards = {
    "storage-and-ingest" = "flowrensic-storage-and-ingest.json"
    "platform"           = "flowrensic-platform.json"
    "judging"            = "flowrensic-judging.json"
  }

  monitoring_parameter_arns = [
    for parameter in compact([
      var.monitoring == "ecs" ? var.grafana_admin_password_parameter : "",
      var.monitoring == "grafana_cloud" ? var.grafana_cloud_token_parameter : "",
    ]) : "arn:${local.partition}:ssm:${var.region}:${local.account}:parameter/${trimprefix(parameter, "/")}"
  ]

  prometheus_config = yamlencode({
    global = { scrape_interval = "15s" }
    scrape_configs = [{
      job_name = "flowrensic"
      dns_sd_configs = [{
        names            = ["server.${var.name}.local"]
        type             = "A"
        port             = local.metrics_port
        refresh_interval = "15s"
      }]
    }]
  })

  grafana_datasource = yamlencode({
    apiVersion = 1
    datasources = [{
      name      = "Prometheus"
      uid       = "prometheus"
      type      = "prometheus"
      access    = "proxy"
      url       = "http://localhost:9090"
      isDefault = true
      editable  = false
    }]
  })

  grafana_dashboard_provider = yamlencode({
    apiVersion = 1
    providers = [{
      name           = "flowrensic"
      folder         = "Flowrensic"
      type           = "file"
      allowUiUpdates = false
      options        = { path = "/tmp/grafana/dashboards" }
    }]
  })

  dashboard_variables = { for key, file in local.dashboards : "DASHBOARD_${upper(replace(key, "-", "_"))}" => file }

  grafana_start = join("\n", concat(
    [
      "set -e",
      "mkdir -p /tmp/grafana/provisioning/datasources /tmp/grafana/provisioning/dashboards /tmp/grafana/dashboards",
      "printf '%s' \"$GRAFANA_DATASOURCE\" > /tmp/grafana/provisioning/datasources/datasource.yml",
      "printf '%s' \"$GRAFANA_DASHBOARD_PROVIDER\" > /tmp/grafana/provisioning/dashboards/dashboards.yml",
    ],
    [for variable, file in local.dashboard_variables : "printf '%s' \"$${${variable}}\" | base64 -d | gunzip > /tmp/grafana/dashboards/${file}"],
    ["exec /run.sh"],
  ))

  # The Prometheus in agent mode beside the server with grafana_cloud. It
  # scrapes the server at the address of the task, which it reads from the ECS
  # task metadata.
  agent_config = <<-EOT
    global:
      scrape_interval: 15s
      external_labels:
        flowrensic_deploy: ${jsonencode(var.name)}
    scrape_configs:
      - job_name: flowrensic
        static_configs:
          - targets: ['TASK_ADDRESS:${local.metrics_port}']
    remote_write:
      - url: ${jsonencode(var.grafana_cloud_prometheus_url)}
        basic_auth:
          username: ${jsonencode(var.grafana_cloud_prometheus_user)}
          password_file: /tmp/agent/token
  EOT

  agent_start = join("\n", [
    "set -e",
    "mkdir -p /tmp/agent",
    "printf '%s' \"$GRAFANA_CLOUD_TOKEN\" > /tmp/agent/token",
    "address=$(wget -qO- \"$ECS_CONTAINER_METADATA_URI_V4\" | sed -n 's/.*\"IPv4Addresses\":\\[\"\\([^\"]*\\)\".*/\\1/p')",
    "printf '%s' \"$AGENT_CONFIG\" | sed \"s/TASK_ADDRESS/$address/\" > /tmp/agent/agent.yml",
    "exec /bin/prometheus --agent --config.file=/tmp/agent/agent.yml --storage.agent.path=/tmp/agent/data --web.listen-address=localhost:9090",
  ])

  agent_container = {
    name       = "collector"
    image      = local.prometheus_image
    essential  = false
    entryPoint = ["sh", "-c"]
    command    = [local.agent_start]
    environment = [
      { name = "AGENT_CONFIG", value = local.agent_config },
    ]
    secrets = [
      { name = "GRAFANA_CLOUD_TOKEN", valueFrom = "arn:${local.partition}:ssm:${var.region}:${local.account}:parameter/${trimprefix(var.grafana_cloud_token_parameter, "/")}" },
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.server.name
        awslogs-region        = var.region
        awslogs-stream-prefix = "collector"
      }
    }
  }
}

# Cloud Map: every server task under server.name.local, for Prometheus.
resource "aws_service_discovery_private_dns_namespace" "monitoring" {
  count = local.monitoring_ecs
  name  = "${var.name}.local"
  vpc   = var.vpc_id
}

resource "aws_service_discovery_service" "server" {
  count = local.monitoring_ecs
  name  = "server"
  dns_config {
    namespace_id   = aws_service_discovery_private_dns_namespace.monitoring[0].id
    routing_policy = "MULTIVALUE"
    dns_records {
      ttl  = 10
      type = "A"
    }
  }
  force_destroy = true
}

# The Prometheus data.
resource "aws_efs_file_system" "prometheus" {
  count          = local.monitoring_ecs
  creation_token = "${var.name}-prometheus"
  encrypted      = true
  tags           = { Name = "${var.name}-prometheus" }
}

resource "aws_efs_mount_target" "prometheus" {
  count           = local.monitoring_ecs * length(var.public_subnet_ids)
  file_system_id  = aws_efs_file_system.prometheus[0].id
  subnet_id       = var.public_subnet_ids[count.index]
  security_groups = [aws_security_group.efs[0].id]
}

# Owned by nobody, the user Prometheus runs as.
resource "aws_efs_access_point" "prometheus" {
  count          = local.monitoring_ecs
  file_system_id = aws_efs_file_system.prometheus[0].id
  posix_user {
    uid = 65534
    gid = 65534
  }
  root_directory {
    path = "/prometheus"
    creation_info {
      owner_uid   = 65534
      owner_gid   = 65534
      permissions = "755"
    }
  }
}

resource "aws_security_group" "monitoring" {
  count       = local.monitoring_ecs
  name        = "${var.name}-monitoring"
  description = "Prometheus and Grafana: the Grafana port from the UI load balancers only."
  vpc_id      = var.vpc_id
}

resource "aws_vpc_security_group_egress_rule" "monitoring_out" {
  count             = local.monitoring_ecs
  security_group_id = aws_security_group.monitoring[0].id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_ingress_rule" "monitoring_from_ui" {
  count                        = local.monitoring_ecs * local.ui_public
  security_group_id            = aws_security_group.monitoring[0].id
  referenced_security_group_id = aws_security_group.ui_public[0].id
  ip_protocol                  = "tcp"
  from_port                    = local.grafana_port
  to_port                      = local.grafana_port
}

resource "aws_vpc_security_group_ingress_rule" "monitoring_from_internal_ui" {
  count                        = local.monitoring_ecs * local.own_internal
  security_group_id            = aws_security_group.monitoring[0].id
  referenced_security_group_id = aws_security_group.ui_internal[0].id
  ip_protocol                  = "tcp"
  from_port                    = local.grafana_port
  to_port                      = local.grafana_port
}

resource "aws_vpc_security_group_ingress_rule" "monitoring_from_user" {
  count                        = local.monitoring_ecs * length(local.internal_lb_security_groups)
  security_group_id            = aws_security_group.monitoring[0].id
  referenced_security_group_id = local.internal_lb_security_groups[count.index]
  ip_protocol                  = "tcp"
  from_port                    = local.grafana_port
  to_port                      = local.grafana_port
}

resource "aws_vpc_security_group_egress_rule" "ui_public_to_grafana" {
  count                        = local.monitoring_ecs * local.ui_public
  security_group_id            = aws_security_group.ui_public[0].id
  referenced_security_group_id = aws_security_group.monitoring[0].id
  ip_protocol                  = "tcp"
  from_port                    = local.grafana_port
  to_port                      = local.grafana_port
}

resource "aws_vpc_security_group_egress_rule" "ui_internal_to_grafana" {
  count                        = local.monitoring_ecs * local.own_internal
  security_group_id            = aws_security_group.ui_internal[0].id
  referenced_security_group_id = aws_security_group.monitoring[0].id
  ip_protocol                  = "tcp"
  from_port                    = local.grafana_port
  to_port                      = local.grafana_port
}

resource "aws_vpc_security_group_ingress_rule" "server_metrics_from_monitoring" {
  count                        = local.monitoring_ecs
  security_group_id            = aws_security_group.server.id
  referenced_security_group_id = aws_security_group.monitoring[0].id
  ip_protocol                  = "tcp"
  from_port                    = local.metrics_port
  to_port                      = local.metrics_port
}

resource "aws_security_group" "efs" {
  count       = local.monitoring_ecs
  name        = "${var.name}-efs"
  description = "The Prometheus data: NFS from the monitoring task only."
  vpc_id      = var.vpc_id
}

resource "aws_vpc_security_group_ingress_rule" "efs" {
  count                        = local.monitoring_ecs
  security_group_id            = aws_security_group.efs[0].id
  referenced_security_group_id = aws_security_group.monitoring[0].id
  ip_protocol                  = "tcp"
  from_port                    = 2049
  to_port                      = 2049
}

# One target group for each UI load balancer, as for the server.
resource "aws_lb_target_group" "grafana" {
  for_each             = local.monitoring_ecs == 1 ? merge(local.ui_public == 1 ? { public = "${var.name}-gf" } : {}, local.internal == 1 ? { internal = "${var.name}-gf-int${local.internal_suffix}" } : {}) : {}
  name                 = each.value
  vpc_id               = var.vpc_id
  target_type          = "ip"
  protocol             = "HTTP"
  port                 = local.grafana_port
  deregistration_delay = 15
  health_check {
    path    = "/api/health"
    port    = tostring(local.grafana_port)
    matcher = "200"
  }
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb_listener_rule" "grafana" {
  for_each     = aws_lb_target_group.grafana
  listener_arn = each.key == "public" ? aws_lb_listener.ui_public[0].arn : local.internal_lb.listener_arn
  action {
    type             = "forward"
    target_group_arn = each.value.arn
  }
  condition {
    host_header {
      values = [local.grafana_name]
    }
  }
}

resource "aws_route53_record" "grafana_public" {
  count   = local.monitoring_ecs * local.ui_public
  zone_id = data.aws_route53_zone.public.zone_id
  name    = local.grafana_name
  type    = "A"
  alias {
    name                   = aws_lb.ui_public[0].dns_name
    zone_id                = aws_lb.ui_public[0].zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "grafana_private" {
  count   = local.monitoring_ecs * local.internal
  zone_id = aws_route53_zone.ui_private[0].zone_id
  name    = local.grafana_name
  type    = "A"
  alias {
    name                   = local.internal_lb.dns_name
    zone_id                = local.internal_lb.zone_id
    evaluate_target_health = false
  }
}

resource "aws_ecs_task_definition" "monitoring" {
  count                    = local.monitoring_ecs
  family                   = "${var.name}-monitoring"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = aws_iam_role.execution.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "ARM64"
  }

  volume {
    name = "prometheus"
    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.prometheus[0].id
      transit_encryption = "ENABLED"
      authorization_config {
        access_point_id = aws_efs_access_point.prometheus[0].id
        iam             = "DISABLED"
      }
    }
  }

  container_definitions = jsonencode([
    {
      name       = "prometheus"
      image      = local.prometheus_image
      essential  = true
      entryPoint = ["sh", "-c"]
      command = [join("\n", [
        "set -e",
        "printf '%s' \"$PROMETHEUS_CONFIG\" > /tmp/prometheus.yml",
        "exec /bin/prometheus --config.file=/tmp/prometheus.yml --storage.tsdb.path=/prometheus --storage.tsdb.retention.time=15d --web.listen-address=localhost:9090",
      ])]
      environment = [{ name = "PROMETHEUS_CONFIG", value = local.prometheus_config }]
      mountPoints = [{ sourceVolume = "prometheus", containerPath = "/prometheus" }]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.server.name
          awslogs-region        = var.region
          awslogs-stream-prefix = "monitoring"
        }
      }
    },
    {
      name         = "grafana"
      image        = local.grafana_image
      essential    = true
      entryPoint   = ["sh", "-c"]
      command      = [local.grafana_start]
      portMappings = [{ containerPort = local.grafana_port, protocol = "tcp" }]
      environment = concat(
        [
          { name = "GF_PATHS_PROVISIONING", value = "/tmp/grafana/provisioning" },
          { name = "GF_SERVER_ROOT_URL", value = "https://${local.grafana_name}" },
          { name = "GF_AUTH_ANONYMOUS_ENABLED", value = "false" },
          { name = "GF_USERS_ALLOW_SIGN_UP", value = "false" },
          { name = "GRAFANA_DATASOURCE", value = local.grafana_datasource },
          { name = "GRAFANA_DASHBOARD_PROVIDER", value = local.grafana_dashboard_provider },
        ],
        [for variable, file in local.dashboard_variables : { name = variable, value = base64gzip(file("${local.dashboards_dir}/${file}")) }],
      )
      secrets = [
        { name = "GF_SECURITY_ADMIN_PASSWORD", valueFrom = local.monitoring_parameter_arns[0] },
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.server.name
          awslogs-region        = var.region
          awslogs-stream-prefix = "monitoring"
        }
      }
    },
  ])
}

# One task at a time: an update stops the old task before it starts the new one.
resource "aws_ecs_service" "monitoring" {
  count                              = local.monitoring_ecs
  name                               = "${var.name}-monitoring"
  cluster                            = aws_ecs_cluster.this.id
  task_definition                    = aws_ecs_task_definition.monitoring[0].arn
  launch_type                        = "FARGATE"
  desired_count                      = 1
  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 100
  health_check_grace_period_seconds  = 120
  wait_for_steady_state              = true

  network_configuration {
    subnets          = var.public_subnet_ids
    security_groups  = [aws_security_group.monitoring[0].id]
    assign_public_ip = true
  }

  dynamic "load_balancer" {
    for_each = aws_lb_target_group.grafana
    content {
      target_group_arn = load_balancer.value.arn
      container_name   = "grafana"
      container_port   = local.grafana_port
    }
  }

  depends_on = [
    aws_lb_listener_rule.grafana,
    aws_efs_mount_target.prometheus,
    aws_iam_role_policy.execution_secrets,
  ]
}

# With grafana_cloud: a folder and the three dashboards in the Grafana of the
# provider the root module configures.
resource "grafana_folder" "flowrensic" {
  count = local.monitoring_cloud
  uid   = var.name
  title = var.grafana_cloud_folder
}

resource "grafana_apps_dashboard_dashboard_v2beta1" "flowrensic" {
  for_each = local.monitoring_cloud == 1 ? local.dashboards : {}
  metadata {
    uid        = "${var.name}-${each.key}"
    folder_uid = grafana_folder.flowrensic[0].uid
  }
  spec {
    json = jsonencode(jsondecode(file("${local.dashboards_dir}/${each.value}")).spec)
  }
  options {
    overwrite        = true
    allow_ui_updates = false
  }
}
