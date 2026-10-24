resource "aws_security_group" "server" {
  name        = "${var.name}-server"
  description = "The Flowrensic server: the main port from the UI load balancers, the ingest port from the ingest load balancer."
  vpc_id      = var.vpc_id
}

resource "aws_vpc_security_group_egress_rule" "server_out" {
  security_group_id = aws_security_group.server.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_ingress_rule" "server_main_from_ui" {
  security_group_id            = aws_security_group.server.id
  referenced_security_group_id = aws_security_group.ui_public.id
  ip_protocol                  = "tcp"
  from_port                    = local.main_port
  to_port                      = local.main_port
}

resource "aws_vpc_security_group_ingress_rule" "server_main_from_internal_ui" {
  count                        = local.internal
  security_group_id            = aws_security_group.server.id
  referenced_security_group_id = aws_security_group.ui_internal[0].id
  ip_protocol                  = "tcp"
  from_port                    = local.main_port
  to_port                      = local.main_port
}

resource "aws_vpc_security_group_ingress_rule" "server_ingest" {
  security_group_id            = aws_security_group.server.id
  referenced_security_group_id = aws_security_group.ingest.id
  ip_protocol                  = "tcp"
  from_port                    = local.ingest_port
  to_port                      = local.ingest_port
}

# The ingest load balancer checks health on the main port.
resource "aws_vpc_security_group_ingress_rule" "server_health_from_ingest" {
  security_group_id            = aws_security_group.server.id
  referenced_security_group_id = aws_security_group.ingest.id
  ip_protocol                  = "tcp"
  from_port                    = local.main_port
  to_port                      = local.main_port
}

resource "aws_security_group" "ui_public" {
  name        = "${var.name}-ui-public"
  description = "The public UI and API load balancer: 443 from the allowed IP ranges only."
  vpc_id      = var.vpc_id
}

resource "aws_vpc_security_group_ingress_rule" "ui_public" {
  count             = length(var.allowed_cidrs)
  security_group_id = aws_security_group.ui_public.id
  cidr_ipv4         = var.allowed_cidrs[count.index]
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

resource "aws_vpc_security_group_egress_rule" "ui_public" {
  security_group_id            = aws_security_group.ui_public.id
  referenced_security_group_id = aws_security_group.server.id
  ip_protocol                  = "tcp"
  from_port                    = local.main_port
  to_port                      = local.main_port
}

resource "aws_security_group" "ui_internal" {
  count       = local.internal
  name        = "${var.name}-ui-internal"
  description = "The internal UI and API load balancer: 443 from the allowed security groups only."
  vpc_id      = var.vpc_id
}

resource "aws_vpc_security_group_ingress_rule" "ui_internal" {
  count                        = length(var.allowed_security_group_ids)
  security_group_id            = aws_security_group.ui_internal[0].id
  referenced_security_group_id = var.allowed_security_group_ids[count.index]
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
}

resource "aws_vpc_security_group_egress_rule" "ui_internal" {
  count                        = local.internal
  security_group_id            = aws_security_group.ui_internal[0].id
  referenced_security_group_id = aws_security_group.server.id
  ip_protocol                  = "tcp"
  from_port                    = local.main_port
  to_port                      = local.main_port
}

resource "aws_security_group" "ingest" {
  name        = "${var.name}-ingest"
  description = "The public ingest load balancer: 443 from anywhere."
  vpc_id      = var.vpc_id
}

resource "aws_vpc_security_group_ingress_rule" "ingest_v4" {
  security_group_id = aws_security_group.ingest.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

resource "aws_vpc_security_group_egress_rule" "ingest_to_server" {
  security_group_id            = aws_security_group.ingest.id
  referenced_security_group_id = aws_security_group.server.id
  ip_protocol                  = "tcp"
  from_port                    = local.main_port
  to_port                      = local.ingest_port
}

resource "aws_security_group" "database" {
  name        = "${var.name}-database"
  description = "The Flowrensic database: 5432 from the server only."
  vpc_id      = var.vpc_id
}

resource "aws_vpc_security_group_ingress_rule" "database" {
  security_group_id            = aws_security_group.database.id
  referenced_security_group_id = aws_security_group.server.id
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
}
