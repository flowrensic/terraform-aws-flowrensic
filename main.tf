data "aws_region" "current" {}
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

# The route table of each public subnet. A subnet with no table of its own,
# such as one of a default VPC, uses the main table of the VPC.
data "aws_route_tables" "public" {
  count  = var.s3_endpoint_id == "" ? length(var.public_subnet_ids) : 0
  vpc_id = var.vpc_id
  filter {
    name   = "association.subnet-id"
    values = [var.public_subnet_ids[count.index]]
  }
}

data "aws_route_table" "main" {
  count  = var.s3_endpoint_id == "" ? 1 : 0
  vpc_id = var.vpc_id
  filter {
    name   = "association.main"
    values = ["true"]
  }
}

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

  internal = length(var.allowed_security_group_ids) > 0 ? 1 : 0

  s3_endpoint_id = var.s3_endpoint_id == "" ? aws_vpc_endpoint.s3[0].id : var.s3_endpoint_id
}

resource "aws_vpc_endpoint" "s3" {
  count             = var.s3_endpoint_id == "" ? 1 : 0
  vpc_id            = var.vpc_id
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids = distinct(flatten([
    for tables in data.aws_route_tables.public : length(tables.ids) > 0 ? tables.ids : [data.aws_route_table.main[0].id]
  ]))
  tags = { Name = "${var.name}-s3" }
}

resource "aws_cloudwatch_log_group" "server" {
  name              = "/ecs/${var.name}"
  retention_in_days = 30
}
