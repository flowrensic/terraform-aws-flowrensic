# Run Flowrensic on AWS with Terraform

This folder is a Terraform module. It runs Flowrensic in a VPC you already have:

- one server on ECS Fargate
- an RDS Postgres database, db.t4g.micro in one zone, with backups kept 7 days
- a private S3 bucket for the histories
- a public load balancer for the UI and API, open only to the IP ranges you give,
  when you give some
- an internal load balancer for the UI and API, open only to the security groups you give,
  when you give some
- a public load balancer for CI jobs, HTTPS on 443, that reaches only the ingest port

Instead of the internal UI load balancer and the ingest load balancer, it can use
load balancers you already have. See Your own load balancers below.
- Prometheus and Grafana with the Flowrensic dashboards, or the dashboards in a
  Grafana Cloud you have, or no monitoring, as the setting monitoring says

It creates no VPC, no NAT and no VPC endpoint. See Networking below. Your settings and your Terraform state stay in your
own repo. The folder example holds a root module that uses this one.

The module is on the Terraform Registry. In your root module:

    module "flowrensic" {
      source  = "flowrensic/flowrensic/aws"
      version = "0.6.4"

      image_version = "0.6.4"
      ...
    }

Each Flowrensic release has a module version with the same number. Give the same
number to version and image_version.

## Before the first apply

1. Copy example/secrets.env.example to .flowrensic-aws-secrets.env in your repo,
   put the real keys in, and add that file name to your .gitignore. Never commit it.
2. Put the keys into SSM:

       ./put-secrets.sh --region eu-west-1 .flowrensic-aws-secrets.env

   After terraform init, the script is in .terraform/modules/flowrensic of your
   root module, with flowrensic the name of your module block.
   Each line of the file is one SSM parameter, NAME=VALUE. The script writes each
   one as a SecureString. Terraform never sees the values, so they are not in the
   state.
3. Run terraform apply in your root module.

The database password is made by RDS and kept by RDS in Secrets Manager. Nobody
types it, and it is not in the state either.

## Settings

Needed:

- region: the AWS region, the same as your provider's.
- image_version: the tag of flowrensic/flowrensic to run.
- vpc_id: the VPC to run in.
- public_subnet_ids: public subnets in two zones. The public load balancers run
  there, and the server too unless you set server_subnet_ids.
- database_subnet_ids: subnets in two zones for the database.
- ui_name: the name of the UI and API, such as flowrensic.internal.example.com.
- ingest_name: the public name CI jobs send to, such as flowrensic-ingest.example.com.
- dns_zone: the public Route 53 zone both names are in.
- envs_parameter: the SSM parameter that holds FLOWRENSIC_ENVS, the env list with its keys.
- required_envs: the envs required to publish history, such as ["prod"]. Each must be an env
  of the env list. The server does not start without it.

With a default:

- name: the start of every resource name, flowrensic.
- image: flowrensic/flowrensic.
- server_subnet_ids: private subnets for the server, empty by default. See
  Networking below.
- server_cpu and server_memory: the size of the server task, 512 and 1024 by
  default, which is 0.5 vCPU and 1 GB. Fargate allows only some pairs: one vCPU,
  1024, needs at least 2048 of memory. A server that pulls many histories needs
  more CPU.
- database_instance_class: the RDS instance class, db.t4g.small by default, which
  has 2 GB of memory.
- alarm_emails: email addresses that get the CloudWatch alarms, empty by default.
  See Alarms below.
- allowed_cidrs: the IP ranges of people that may open the UI and API.
- allowed_security_group_ids: the security groups of servers in the same VPC that
  may call the UI and API. Inside the VPC, ui_name points at the internal load balancer.
- secret_parameters: more server variables, each read from an SSM parameter, such as
  a Temporal Cloud key that the env list reads through temporalReadApiKeyVariable, or a
  key that can write, read through temporalWriteApiKeyVariable, which the Remediate
  button needs.
- monitoring: ecs, grafana_cloud or none, ecs by default. See Monitoring below.
- grafana_admin_password_parameter: with ecs, the SSM parameter that holds the
  password of the Grafana user admin. Needed with ecs.
- grafana_cloud_prometheus_url, grafana_cloud_prometheus_user and
  grafana_cloud_token_parameter: with grafana_cloud, the remote write URL and the
  user of the Prometheus of your stack, and the SSM parameter that holds a token
  that can write metrics. All three are needed with grafana_cloud.
- grafana_cloud_folder: with grafana_cloud, the folder the dashboards go in, Flowrensic.
- public_listener_arn: the HTTPS listener on 443 of an internet-facing load balancer
  you have, for the ingest. Empty by default.
- internal_listener_arn: the HTTPS listener on 443 of an internal load balancer you
  have, for the UI and API. Empty by default.
- public_listener_rule_priority: the priority of the ingest rule on
  public_listener_arn, from 1 to 50000. Null by default, the next free one.
- internal_listener_rule_priority: the priority of the UI rule on
  internal_listener_arn, from 1 to 49999. With monitoring ecs the Grafana rule
  gets the next number. Null by default, the next free one.

## Networking

The server needs to reach Docker Hub for its image, SSM, Secrets Manager,
CloudWatch Logs, S3 and Temporal Cloud. The module creates no NAT and no VPC
endpoint, and does not change your route tables. You pick one of two ways.

- No NAT, the default. Leave server_subnet_ids empty. The server runs in
  public_subnet_ids with a public IP and goes out through the internet gateway of
  the VPC. Its security group lets nothing in from the internet.
- A NAT you already have. Set server_subnet_ids to private subnets in two zones
  whose route table sends traffic to the internet through that NAT. The server
  runs there with no public IP. The module does not check the routes, so a subnet
  with no way out leaves the server unable to pull its image.

Either way the load balancers stay in public_subnet_ids and the database in
database_subnet_ids. With monitoring ecs, the Prometheus and Grafana task runs in
the same subnets as the server, the same way, and so do its EFS mount targets.

## Your own load balancers

With public_listener_arn, the module makes no ingest load balancer. It adds a rule
to that listener that sends ingest_name to the ingest port, and ingest_name points
at that load balancer.

With internal_listener_arn, the module makes no internal UI load balancer. It adds
a rule to that listener that sends ui_name to the UI, and with monitoring ecs one
that sends grafana. and ui_name to Grafana. Inside the VPC ui_name points at that
load balancer. Its security groups decide who reaches the UI, so
allowed_security_group_ids must be empty.

Both must be application load balancers in vpc_id. The module adds its own
certificate to each listener. It changes nothing else of your load balancers. Their security groups must let them out to the
server, as a new security group does. The server lets in their security groups.

By default the rules get the next free priority, so they come after your rules.
If one of your rules matches the Flowrensic names too, such as a rule for any host
under your domain, or for a path like / or /api/auth on any host, it answers first
and the UI or ingest never sees the call. Set public_listener_rule_priority and
internal_listener_rule_priority to put the module's rules first. Each rule matches
only its own host name, so this changes nothing for other hosts. Pick a low number
that is free on the listener, such as 1. With monitoring ecs the Grafana rule takes
the next number on the internal listener, so that one must be free too. AWS fails
the apply when a number is taken.

allowed_cidrs still makes a public UI load balancer of the module, since your
public one is open to everyone. To have no load balancer of the module at all, give
both listeners and leave allowed_cidrs empty.

## Monitoring

With monitoring ecs, one more ECS service runs Prometheus and Grafana. Open
Grafana at https://grafana. and ui_name, such as
https://grafana.flowrensic.internal.example.com, and log in as admin with the
password in grafana_admin_password_parameter. The same IP ranges and security
groups as the UI reach it. The folder Flowrensic holds three dashboards: Flowrensic
storage and ingest, Flowrensic platform and Flowrensic judging.

Prometheus finds every server task through Cloud Map, scrapes it every 15 seconds,
and keeps 15 days of data on an encrypted EFS file system. Prometheus does not
support NFS file systems such as EFS for its data, so the data can be corrupt after
a crash. Prometheus then does not start, and its log says why. Delete the folder on
the file system, or the file system with an apply of monitoring none and then ecs
again, and the history kept so far is lost.

With monitoring grafana_cloud, a small Prometheus in agent mode runs beside the
server, scrapes it, and sends what it scrapes to your Grafana Cloud, with the label
flowrensic_deploy set to name. The module also puts the three dashboards into the
folder grafana_cloud_folder of that Grafana. For that your root module configures
the grafana provider with the URL of your stack and its ID in stack_id, and terraform runs with a service
account token in GRAFANA_AUTH. The service account needs the Admin role: with Editor,
Grafana lets it create the folder but not read it back, and the apply fails. That
token is not kept in the state. The token that writes metrics goes into SSM with put-secrets.sh, like
the other keys. The dashboards add up every series of job flowrensic, so one Grafana
Cloud stack takes one Flowrensic deploy.

With monitoring none there is neither. The server still serves its metrics on port
9464. To scrape them with a Prometheus of your own, open that port in the security
group of the server to it.

Moving between the settings is an apply. Leaving ecs deletes the Prometheus data.
The certificate names grafana. and ui_name only with ecs, so moving to or from ecs
makes a new certificate.

## Updates

Change version and image_version to the new release and run terraform init and
terraform apply. The old server stops before the new
one starts, so Flowrensic is away for a minute or two.

## When a key changes

Change the line in .flowrensic-aws-secrets.env and run the script again with the
cluster and the service from the outputs. It starts the server again so the new
key is used:

    ./put-secrets.sh --region eu-west-1 --restart CLUSTER SERVICE .flowrensic-aws-secrets.env

## The database password

RDS changes the password once a year. The server reads it only when it starts, so
after RDS changes it the server cannot open new database connections. Start it
again with:

    aws ecs update-service --cluster CLUSTER --service SERVICE --force-new-deployment

## Destroy

terraform destroy removes everything, the histories in the bucket too. The database
has no deletion protection and no final snapshot.

## Alarms

The module puts CloudWatch alarms on the server and the database and sends them to
the SNS topic of the output alarm_topic. Each address of alarm_emails gets them by
email after it confirms the first message. An alarm fires when:

- a server task stops by itself, such as killed for running out of memory
- no healthy server is behind a target group for 3 minutes
- the server answers 5 or more 5xx in 5 minutes
- the server task uses more than 80% of its memory for 3 minutes, or of its CPU
  for 10 minutes
- the database has less than 100 MB free memory or uses more than 50 MB of swap
  for 15 minutes
- the database, of a db.t class, has fewer than 5 CPU credits left
- the database has less than 10% of its storage free
- the database uses more than 80% of its CPU for 15 minutes
