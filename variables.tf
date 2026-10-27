variable "region" {
  description = "The AWS region, the same as the region of the provider."
  type        = string
}

variable "image_version" {
  description = "The tag of the Flowrensic image to run, such as 0.5.11."
  type        = string
}

variable "vpc_id" {
  description = "The VPC Flowrensic runs in."
  type        = string
}

variable "public_subnet_ids" {
  description = "Public subnets in at least two zones, for the server and the public load balancers."
  type        = list(string)
}

variable "database_subnet_ids" {
  description = "Subnets in at least two zones, for the database."
  type        = list(string)
}

variable "ui_name" {
  description = "The name people and servers open the UI and API at, such as flowrensic.internal.example.com."
  type        = string
}

variable "ingest_name" {
  description = "The public name CI jobs send their data to, such as flowrensic-ingest.example.com."
  type        = string
}

variable "dns_zone" {
  description = "The public Route 53 zone both names are in, such as example.com."
  type        = string
}

variable "envs_parameter" {
  description = "The name of the SSM SecureString parameter that holds FLOWRENSIC_ENVS."
  type        = string
}

variable "required_envs" {
  description = "The envs required to publish history, FLOWRENSIC_REQUIRED_ENVS. Each must be an env of FLOWRENSIC_ENVS."
  type        = list(string)

  validation {
    condition     = length(var.required_envs) > 0
    error_message = "required_envs needs at least one env."
  }
}

variable "name" {
  description = "The start of every resource name."
  type        = string
  default     = "flowrensic"
}

variable "image" {
  description = "The Flowrensic image, without the tag."
  type        = string
  default     = "flowrensic/flowrensic"
}

variable "server_cpu" {
  description = "The CPU units of the server task: 1024 is one vCPU. Fargate allows 256, 512, 1024, 2048, 4096, 8192 and 16384."
  type        = number
  default     = 512
}

variable "server_memory" {
  description = "The memory of the server task in MiB. Fargate allows only some sizes for each server_cpu, 2048 to 8192 for 1024."
  type        = number
  default     = 1024
}

variable "allowed_cidrs" {
  description = "IP ranges of people that may reach the UI and API, each a CIDR such as an address with /32."
  type        = list(string)
  default     = []
}

variable "server_subnet_ids" {
  description = "Private subnets for the server and the monitoring task, which then get no public IP. The VPC must route them to the internet, such as through a NAT. Empty runs them in public_subnet_ids with a public IP."
  type        = list(string)
  default     = []
}

variable "allowed_security_group_ids" {
  description = "Security groups of servers in the VPC that may reach the UI and API."
  type        = list(string)
  default     = []
}

variable "secret_parameters" {
  description = "More variables of the server, each read from the SSM parameter it names."
  type        = map(string)
  default     = {}
}

variable "monitoring" {
  description = "Where the server's metrics and the Flowrensic dashboards go: ecs runs Prometheus and Grafana in the cluster, grafana_cloud sends them to a Grafana Cloud you have, none sends them nowhere."
  type        = string
  default     = "ecs"
  validation {
    condition     = contains(["ecs", "grafana_cloud", "none"], var.monitoring)
    error_message = "monitoring is one of ecs, grafana_cloud or none."
  }
}

variable "grafana_admin_password_parameter" {
  description = "With monitoring ecs: the SSM SecureString parameter that holds the password of the Grafana user admin."
  type        = string
  default     = ""
  validation {
    condition     = var.monitoring != "ecs" || var.grafana_admin_password_parameter != ""
    error_message = "monitoring ecs needs grafana_admin_password_parameter, the SSM parameter that holds the Grafana admin password."
  }
}

variable "grafana_cloud_prometheus_url" {
  description = "With monitoring grafana_cloud: the Prometheus remote write URL of the Grafana Cloud stack, ending in /api/prom/push."
  type        = string
  default     = ""
  validation {
    condition     = var.monitoring != "grafana_cloud" || var.grafana_cloud_prometheus_url != ""
    error_message = "monitoring grafana_cloud needs grafana_cloud_prometheus_url, the Prometheus remote write URL of the stack."
  }
}

variable "grafana_cloud_prometheus_user" {
  description = "With monitoring grafana_cloud: the user of the Prometheus of the stack, a number."
  type        = string
  default     = ""
  validation {
    condition     = var.monitoring != "grafana_cloud" || var.grafana_cloud_prometheus_user != ""
    error_message = "monitoring grafana_cloud needs grafana_cloud_prometheus_user, the user of the Prometheus of the stack."
  }
}

variable "grafana_cloud_token_parameter" {
  description = "With monitoring grafana_cloud: the SSM SecureString parameter that holds a Grafana Cloud token that can write metrics."
  type        = string
  default     = ""
  validation {
    condition     = var.monitoring != "grafana_cloud" || var.grafana_cloud_token_parameter != ""
    error_message = "monitoring grafana_cloud needs grafana_cloud_token_parameter, the SSM parameter that holds the token that writes metrics."
  }
}

variable "grafana_cloud_folder" {
  description = "With monitoring grafana_cloud: the folder the dashboards go in."
  type        = string
  default     = "Flowrensic"
}

variable "public_listener_arn" {
  description = "The HTTPS listener on 443 of an internet-facing application load balancer you have in vpc_id. When set, ingest_name goes to that load balancer by a host rule, and the module makes no ingest load balancer."
  type        = string
  default     = ""
  validation {
    condition     = var.public_listener_arn == "" || can(regex("^arn:[^:]+:elasticloadbalancing:[^:]+:[0-9]+:listener/app/", var.public_listener_arn))
    error_message = "public_listener_arn is the ARN of a listener of an application load balancer, or empty."
  }
}

variable "internal_listener_arn" {
  description = "The HTTPS listener on 443 of an internal application load balancer you have in vpc_id. When set, ui_name goes to that load balancer by a host rule inside the VPC, and the module makes no internal UI load balancer. Its security groups decide who reaches the UI."
  type        = string
  default     = ""
  validation {
    condition     = var.internal_listener_arn == "" || can(regex("^arn:[^:]+:elasticloadbalancing:[^:]+:[0-9]+:listener/app/", var.internal_listener_arn))
    error_message = "internal_listener_arn is the ARN of a listener of an application load balancer, or empty."
  }
  validation {
    condition     = var.internal_listener_arn == "" || length(var.allowed_security_group_ids) == 0
    error_message = "With internal_listener_arn, the security groups of that load balancer decide who reaches the UI, so allowed_security_group_ids must be empty."
  }
}

variable "public_listener_rule_priority" {
  description = "The priority of the ingest rule on public_listener_arn. Null gives it the next free priority, after your rules."
  type        = number
  default     = null
  validation {
    condition     = var.public_listener_rule_priority == null || try(var.public_listener_rule_priority >= 1 && var.public_listener_rule_priority <= 50000 && floor(var.public_listener_rule_priority) == var.public_listener_rule_priority, false)
    error_message = "public_listener_rule_priority is a whole number from 1 to 50000, or null."
  }
}

variable "internal_listener_rule_priority" {
  description = "The priority of the UI rule on internal_listener_arn. With monitoring ecs the Grafana rule gets the next number. Null gives them the next free priorities, after your rules."
  type        = number
  default     = null
  validation {
    condition     = var.internal_listener_rule_priority == null || try(var.internal_listener_rule_priority >= 1 && var.internal_listener_rule_priority <= 49999 && floor(var.internal_listener_rule_priority) == var.internal_listener_rule_priority, false)
    error_message = "internal_listener_rule_priority is a whole number from 1 to 49999, or null."
  }
}
