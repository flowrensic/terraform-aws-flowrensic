# A root module that uses the Flowrensic module. Copy it into your own repo
# and put your own values in.

terraform {
  required_version = ">= 1.11"
  required_providers {
    aws     = { source = "hashicorp/aws", version = ">= 6.0" }
    grafana = { source = "grafana/grafana", version = ">= 4.50" }
  }
  # Keep the state in your own backend, such as an S3 bucket.
}

provider "aws" {
  region = "eu-west-1"
}

# Used only with monitoring grafana_cloud: the URL and ID of your Grafana Cloud stack.
# Without stack_id, Grafana Cloud refuses the dashboards with 403.
# The token comes from GRAFANA_AUTH when terraform runs, so it is not in the state.
provider "grafana" {
  url      = "https://example.grafana.net"
  stack_id = 123456
}

module "flowrensic" {
  source  = "flowrensic/flowrensic/aws"
  version = "0.6.29"

  region              = "eu-west-1"
  image_version       = "0.6.4"
  vpc_id              = "vpc-REPLACE"
  public_subnet_ids   = ["subnet-PUBLIC-A", "subnet-PUBLIC-B"]
  database_subnet_ids = ["subnet-PRIVATE-A", "subnet-PRIVATE-B"]

  # When the VPC has a NAT, the server can run in private subnets with no public IP.
  # server_subnet_ids = ["subnet-PRIVATE-A", "subnet-PRIVATE-B"]
  ui_name        = "flowrensic.internal.example.com"
  ingest_name    = "flowrensic-ingest.example.com"
  dns_zone       = "example.com"
  envs_parameter = "/flowrensic/envs"
  required_envs  = ["prod"]

  # People, by IP range, and servers in the same VPC, by security group.
  allowed_cidrs              = ["192.0.2.10/32"]
  allowed_security_group_ids = ["sg-REPLACE"]

  # Or load balancers you already have, by a host rule on their HTTPS listeners.
  # With internal_listener_arn, leave allowed_security_group_ids empty.
  # public_listener_arn   = "arn:aws:elasticloadbalancing:eu-west-1:111122223333:listener/app/public/REPLACE/REPLACE"
  # internal_listener_arn = "arn:aws:elasticloadbalancing:eu-west-1:111122223333:listener/app/internal/REPLACE/REPLACE"
  # Put the module's rules before yours, at a free priority. Grafana takes the next one.
  # public_listener_rule_priority   = 1
  # internal_listener_rule_priority = 1

  # The Temporal Cloud keys the env list reads through temporalReadApiKeyVariable,
  # and through temporalWriteApiKeyVariable for the Remediate button.
  secret_parameters = {
    TEMPORAL_CLOUD_READ_API_KEY  = "/flowrensic/temporal-cloud-read-api-key"
    TEMPORAL_CLOUD_WRITE_API_KEY = "/flowrensic/temporal-cloud-write-api-key"
  }

  # Prometheus and Grafana in the cluster, at grafana. and ui_name.
  monitoring                       = "ecs"
  grafana_admin_password_parameter = "/flowrensic/grafana-admin-password"

  # Or a Grafana Cloud you already have:
  # monitoring                    = "grafana_cloud"
  # grafana_cloud_prometheus_url  = "https://prometheus-prod-01-eu-west-0.grafana.net/api/prom/push"
  # grafana_cloud_prometheus_user = "123456"
  # grafana_cloud_token_parameter = "/flowrensic/grafana-cloud-token"
}

output "ui_url" {
  value = module.flowrensic.ui_url
}

output "ingest_url" {
  value = module.flowrensic.ingest_url
}

output "grafana_url" {
  value = module.flowrensic.grafana_url
}

output "restart" {
  value = "put-secrets.sh --region eu-west-1 --restart ${module.flowrensic.cluster} ${module.flowrensic.service} .flowrensic-aws-secrets.env"
}
