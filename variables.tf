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

variable "mode" {
  description = "full runs the server with an RDS Postgres database. standalone runs the flowrensic-standalone image, which holds its own Postgres, with no RDS and no volume, so its data is lost when the task stops."
  type        = string
  default     = "full"
  validation {
    condition     = contains(["full", "standalone"], var.mode)
    error_message = "mode is full or standalone."
  }
}

variable "database_subnet_ids" {
  description = "With mode full: subnets in at least two zones, for the database."
  type        = list(string)
  default     = []
  validation {
    condition     = var.mode != "full" || length(var.database_subnet_ids) > 0
    error_message = "full mode needs database_subnet_ids, subnets in two zones for the database."
  }
  validation {
    condition     = var.mode != "standalone" || length(var.database_subnet_ids) == 0
    error_message = "database_subnet_ids is not used in standalone mode, which has no RDS. Leave it out."
  }
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
  description = "The name of the SSM SecureString parameter that holds FLOWRENSIC_KNOWN_ENVS."
  type        = string
}

variable "name" {
  description = "The start of every resource name."
  type        = string
  default     = "flowrensic"
}

variable "image" {
  description = "The Flowrensic image, without the tag. Null is flowrensic/flowrensic in full mode and flowrensic/flowrensic-standalone in standalone mode."
  type        = string
  default     = null
}

variable "server_cpu" {
  description = "The CPU units of the server task: 1024 is one vCPU. Fargate allows 256, 512, 1024, 2048, 4096, 8192 and 16384. Null is 512 in full mode and 1024 in standalone mode."
  type        = number
  default     = null
}

variable "server_memory" {
  description = "The memory of the server task in MiB. Fargate allows only some sizes for each server_cpu, 2048 to 8192 for 1024. Null is 1024 in full mode and 4096 in standalone mode, where Postgres runs in the task too."
  type        = number
  default     = null
}

variable "ephemeral_storage_gib" {
  description = "The Fargate ephemeral storage of the server task in GiB, from 21 to 200. Null is 50 in standalone mode, where the database is kept there, and the Fargate default of 20 in full mode."
  type        = number
  default     = null
  validation {
    condition     = var.ephemeral_storage_gib == null || try(var.ephemeral_storage_gib >= 21 && var.ephemeral_storage_gib <= 200 && floor(var.ephemeral_storage_gib) == var.ephemeral_storage_gib, false)
    error_message = "ephemeral_storage_gib is a whole number from 21 to 200, or null."
  }
}

variable "database_instance_class" {
  description = "With mode full: the RDS instance class of the database. Null is db.t4g.small."
  type        = string
  default     = null
  validation {
    condition     = var.mode != "standalone" || var.database_instance_class == null
    error_message = "database_instance_class is not used in standalone mode, which has no RDS. Leave it out."
  }
}

variable "database_pool_size" {
  description = "The most database connections the ingest calls and the background jobs of one server hold, FLOWRENSIC_DATABASE_POOL_SIZE."
  type        = number
  default     = 24
}

variable "database_call_pool_size" {
  description = "The most database connections the UI and API calls of one server hold, FLOWRENSIC_DATABASE_CALL_POOL_SIZE, apart from the ingest calls and the background jobs."
  type        = number
  default     = 6
}

variable "alarm_topic_arn" {
  description = "An SNS topic the user already has, which gets the CloudWatch alarms of the module. Its policy has to let events.amazonaws.com publish. Empty makes a topic of the module's own."
  type        = string
  default     = ""
}

variable "alarm_emails" {
  description = "Email addresses that get the alarms on the module's own topic, only without alarm_topic_arn. Each one confirms the subscription from the first email."
  type        = list(string)
  default     = []
  validation {
    condition     = length(var.alarm_emails) == 0 || var.alarm_topic_arn == ""
    error_message = "alarm_emails is only for the module's own topic. With alarm_topic_arn, subscribe to that topic instead."
  }
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

variable "enable_execute_command" {
  description = "Allow ECS Exec into the server task (aws ecs execute-command), for looking at the database and files inside it. Off by default."
  type        = bool
  default     = false
}
