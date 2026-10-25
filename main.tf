data "aws_region" "current" {}
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  account   = data.aws_caller_identity.current.account_id
  partition = data.aws_partition.current.partition

  main_port   = 8080
  ingest_port = 8081

  envs_parameter_arn = "arn:${local.partition}:ssm:${var.region}:${local.account}:parameter/${trimprefix(var.envs_parameter, "/")}"
  secret_parameter_arns = {
    for variable, parameter in var.secret_parameters :
    variable => "arn:${local.partition}:ssm:${var.region}:${local.account}:parameter/${trimprefix(parameter, "/")}"
  }

  # Which load balancers are the module's own and which are the user's.
  ui_public      = length(var.allowed_cidrs) > 0 ? 1 : 0
  reuse_public   = var.public_listener_arn != "" ? 1 : 0
  reuse_internal = var.internal_listener_arn != "" ? 1 : 0
  own_ingest     = 1 - local.reuse_public
  own_internal   = local.reuse_internal == 0 && length(var.allowed_security_group_ids) > 0 ? 1 : 0
  internal       = max(local.own_internal, local.reuse_internal)

  # Where the server and the monitoring task run, and whether they get a public IP.
  task_subnet_ids  = length(var.server_subnet_ids) > 0 ? var.server_subnet_ids : var.public_subnet_ids
  assign_public_ip = length(var.server_subnet_ids) == 0
}

resource "aws_cloudwatch_log_group" "server" {
  name              = "/ecs/${var.name}"
  retention_in_days = 30
}
