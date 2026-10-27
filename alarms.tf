# CloudWatch alarms on the critical metrics of the server and the database.
# Each alarm, and each server task that stops by itself, goes to the SNS topic
# of alarm_topic_arn. Without one, the module makes a topic of its own and the
# addresses of alarm_emails get it by email.

locals {
  own_alarm_topic = var.alarm_topic_arn == "" ? 1 : 0
  alarm_topic     = local.own_alarm_topic == 1 ? aws_sns_topic.alarms[0].arn : var.alarm_topic_arn
  alarm_actions   = [local.alarm_topic]

  # The target groups the server is in, each with its load balancer.
  alarm_target_groups = merge(
    { ingest = { target_group = aws_lb_target_group.ingest.arn_suffix, load_balancer = local.ingest_lb.arn_suffix } },
    local.ui_public == 1 ? { ui-public = { target_group = aws_lb_target_group.ui_public[0].arn_suffix, load_balancer = aws_lb.ui_public[0].arn_suffix } } : {},
    local.internal == 1 ? { ui-internal = { target_group = aws_lb_target_group.ui_internal[0].arn_suffix, load_balancer = local.internal_lb.arn_suffix } } : {},
  )

  server_dimensions   = { ClusterName = aws_ecs_cluster.this.name, ServiceName = aws_ecs_service.server.name }
  database_dimensions = { DBInstanceIdentifier = aws_db_instance.this.identifier }
}

resource "aws_sns_topic" "alarms" {
  count = local.own_alarm_topic
  name  = "${var.name}-alarms"
}

resource "aws_sns_topic_subscription" "alarms" {
  for_each  = local.own_alarm_topic == 1 ? toset(var.alarm_emails) : toset([])
  topic_arn = aws_sns_topic.alarms[0].arn
  protocol  = "email"
  endpoint  = each.value
}

data "aws_iam_policy_document" "alarms_topic" {
  count = local.own_alarm_topic
  statement {
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.alarms[0].arn]
    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com", "cloudwatch.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account]
    }
  }
}

resource "aws_sns_topic_policy" "alarms" {
  count  = local.own_alarm_topic
  arn    = aws_sns_topic.alarms[0].arn
  policy = data.aws_iam_policy_document.alarms_topic[0].json
}

# A server task whose container exits with a code other than 0, such as 137
# when it ran out of memory. A task stopped by a deploy exits with 0.
resource "aws_cloudwatch_event_rule" "server_stopped" {
  name        = "${var.name}-server-stopped"
  description = "A Flowrensic server task stopped by itself."
  event_pattern = jsonencode({
    source      = ["aws.ecs"]
    detail-type = ["ECS Task State Change"]
    detail = {
      clusterArn = [aws_ecs_cluster.this.arn]
      lastStatus = ["STOPPED"]
      containers = { name = ["server"], exitCode = [{ anything-but = 0 }] }
    }
  })
}

resource "aws_cloudwatch_event_target" "server_stopped" {
  rule = aws_cloudwatch_event_rule.server_stopped.name
  arn  = local.alarm_topic
  input_transformer {
    input_paths = {
      task   = "$.detail.taskArn"
      reason = "$.detail.stoppedReason"
      exit   = "$.detail.containers[0].exitCode"
      why    = "$.detail.containers[0].reason"
    }
    input_template = "\"Flowrensic server task <task> stopped by itself: <reason>, exit code <exit>, <why>.\""
  }
}

resource "aws_cloudwatch_metric_alarm" "no_server" {
  for_each            = local.alarm_target_groups
  alarm_name          = "${var.name}-no-healthy-server-${each.key}"
  alarm_description   = "No healthy Flowrensic server is behind the ${each.key} target group, so calls get 502 or 503."
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HealthyHostCount"
  dimensions          = { TargetGroup = each.value.target_group, LoadBalancer = each.value.load_balancer }
  statistic           = "Minimum"
  period              = 60
  evaluation_periods  = 3
  comparison_operator = "LessThanThreshold"
  threshold           = 1
  treat_missing_data  = "breaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
}

resource "aws_cloudwatch_metric_alarm" "server_errors" {
  for_each            = local.alarm_target_groups
  alarm_name          = "${var.name}-server-errors-${each.key}"
  alarm_description   = "The Flowrensic server answered 5xx behind the ${each.key} target group."
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HTTPCode_Target_5XX_Count"
  dimensions          = { TargetGroup = each.value.target_group, LoadBalancer = each.value.load_balancer }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = 5
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
}

resource "aws_cloudwatch_metric_alarm" "server_memory" {
  alarm_name          = "${var.name}-server-memory"
  alarm_description   = "The Flowrensic server task uses more than 80% of its memory. At 100% ECS kills it."
  namespace           = "AWS/ECS"
  metric_name         = "MemoryUtilization"
  dimensions          = local.server_dimensions
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 3
  comparison_operator = "GreaterThanThreshold"
  threshold           = 80
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
}

resource "aws_cloudwatch_metric_alarm" "server_cpu" {
  alarm_name          = "${var.name}-server-cpu"
  alarm_description   = "The Flowrensic server task uses more than 80% of its CPU for 10 minutes."
  namespace           = "AWS/ECS"
  metric_name         = "CPUUtilization"
  dimensions          = local.server_dimensions
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  comparison_operator = "GreaterThanThreshold"
  threshold           = 80
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
}

resource "aws_cloudwatch_metric_alarm" "database_memory" {
  alarm_name          = "${var.name}-database-memory"
  alarm_description   = "The Flowrensic database has less than 100 MB of free memory for 15 minutes."
  namespace           = "AWS/RDS"
  metric_name         = "FreeableMemory"
  dimensions          = local.database_dimensions
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 3
  comparison_operator = "LessThanThreshold"
  threshold           = 100 * 1024 * 1024
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
}

resource "aws_cloudwatch_metric_alarm" "database_swap" {
  alarm_name          = "${var.name}-database-swap"
  alarm_description   = "The Flowrensic database uses more than 50 MB of swap for 15 minutes, so its memory is too small."
  namespace           = "AWS/RDS"
  metric_name         = "SwapUsage"
  dimensions          = local.database_dimensions
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 3
  comparison_operator = "GreaterThanThreshold"
  threshold           = 50 * 1024 * 1024
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
}

resource "aws_cloudwatch_metric_alarm" "database_cpu_credits" {
  count               = startswith(var.database_instance_class, "db.t") ? 1 : 0
  alarm_name          = "${var.name}-database-cpu-credits"
  alarm_description   = "The Flowrensic database has used almost all its CPU credits, so it runs on paid surplus credits."
  namespace           = "AWS/RDS"
  metric_name         = "CPUCreditBalance"
  dimensions          = local.database_dimensions
  statistic           = "Minimum"
  period              = 300
  evaluation_periods  = 1
  comparison_operator = "LessThanThreshold"
  threshold           = 5
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
}

resource "aws_cloudwatch_metric_alarm" "database_storage" {
  alarm_name          = "${var.name}-database-storage"
  alarm_description   = "The Flowrensic database has less than 10% of its storage free."
  namespace           = "AWS/RDS"
  metric_name         = "FreeStorageSpace"
  dimensions          = local.database_dimensions
  statistic           = "Minimum"
  period              = 300
  evaluation_periods  = 1
  comparison_operator = "LessThanThreshold"
  threshold           = aws_db_instance.this.allocated_storage * 1024 * 1024 * 1024 / 10
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
}

resource "aws_cloudwatch_metric_alarm" "database_cpu" {
  alarm_name          = "${var.name}-database-cpu"
  alarm_description   = "The Flowrensic database uses more than 80% of its CPU for 15 minutes."
  namespace           = "AWS/RDS"
  metric_name         = "CPUUtilization"
  dimensions          = local.database_dimensions
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 3
  comparison_operator = "GreaterThanThreshold"
  threshold           = 80
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
}
