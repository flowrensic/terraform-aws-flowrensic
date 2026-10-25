locals {
  health_check = {
    path    = "/readyz"
    port    = tostring(local.main_port)
    matcher = "200"
  }

  # A target group on a load balancer of the user has another name than one on
  # the module's own, so moving between them makes the new one first. Every
  # target group is deleted only after the server service has left it.
  public_suffix   = local.reuse_public == 1 ? "-x" : ""
  internal_suffix = local.reuse_internal == 1 ? "-x" : ""

  # The load balancer each name points at, the module's own or the user's.
  ingest_lb = local.reuse_public == 1 ? {
    arn      = data.aws_lb.public[0].arn
    dns_name = data.aws_lb.public[0].dns_name
    zone_id  = data.aws_lb.public[0].zone_id
    } : {
    arn      = aws_lb.ingest[0].arn
    dns_name = aws_lb.ingest[0].dns_name
    zone_id  = aws_lb.ingest[0].zone_id
  }

  internal_lb = local.reuse_internal == 1 ? {
    listener_arn = var.internal_listener_arn
    dns_name     = data.aws_lb.internal[0].dns_name
    zone_id      = data.aws_lb.internal[0].zone_id
    } : local.own_internal == 1 ? {
    listener_arn = aws_lb_listener.ui_internal[0].arn
    dns_name     = aws_lb.ui_internal[0].dns_name
    zone_id      = aws_lb.ui_internal[0].zone_id
  } : null

  # The security groups of the user's load balancers, which the server lets in.
  public_lb_security_groups   = local.reuse_public == 1 ? sort(tolist(data.aws_lb.public[0].security_groups)) : []
  internal_lb_security_groups = local.reuse_internal == 1 ? sort(tolist(data.aws_lb.internal[0].security_groups)) : []
}

# The user's load balancers, read from the listeners given.
data "aws_lb_listener" "public" {
  count = local.reuse_public
  arn   = var.public_listener_arn
  lifecycle {
    postcondition {
      condition     = self.protocol == "HTTPS" && self.port == 443
      error_message = "public_listener_arn must be an HTTPS listener on port 443."
    }
  }
}

data "aws_lb" "public" {
  count = local.reuse_public
  arn   = data.aws_lb_listener.public[0].load_balancer_arn
  lifecycle {
    postcondition {
      condition     = !self.internal && self.load_balancer_type == "application" && self.vpc_id == var.vpc_id
      error_message = "public_listener_arn must be a listener of an internet-facing load balancer, an application load balancer in vpc_id."
    }
  }
}

data "aws_lb_listener" "internal" {
  count = local.reuse_internal
  arn   = var.internal_listener_arn
  lifecycle {
    postcondition {
      condition     = self.protocol == "HTTPS" && self.port == 443
      error_message = "internal_listener_arn must be an HTTPS listener on port 443."
    }
  }
}

data "aws_lb" "internal" {
  count = local.reuse_internal
  arn   = data.aws_lb_listener.internal[0].load_balancer_arn
  lifecycle {
    postcondition {
      condition     = self.internal && self.load_balancer_type == "application" && self.vpc_id == var.vpc_id
      error_message = "internal_listener_arn must be a listener of an internal load balancer, an application load balancer in vpc_id."
    }
  }
}

resource "aws_lb" "ui_public" {
  count              = local.ui_public
  name               = "${var.name}-ui"
  load_balancer_type = "application"
  internal           = false
  subnets            = var.public_subnet_ids
  security_groups    = [aws_security_group.ui_public[0].id]
}

resource "aws_lb" "ui_internal" {
  count              = local.own_internal
  name               = "${var.name}-ui-int"
  load_balancer_type = "application"
  internal           = true
  subnets            = var.public_subnet_ids
  security_groups    = [aws_security_group.ui_internal[0].id]
}

resource "aws_lb" "ingest" {
  count              = local.own_ingest
  name               = "${var.name}-ingest"
  load_balancer_type = "application"
  internal           = false
  subnets            = var.public_subnet_ids
  security_groups    = [aws_security_group.ingest[0].id]
}

resource "aws_lb_target_group" "ui_public" {
  count                = local.ui_public
  name                 = "${var.name}-ui"
  vpc_id               = var.vpc_id
  target_type          = "ip"
  protocol             = "HTTP"
  port                 = local.main_port
  deregistration_delay = 15
  health_check {
    path    = local.health_check.path
    port    = local.health_check.port
    matcher = local.health_check.matcher
  }
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb_target_group" "ui_internal" {
  count                = local.internal
  name                 = "${var.name}-ui-int${local.internal_suffix}"
  vpc_id               = var.vpc_id
  target_type          = "ip"
  protocol             = "HTTP"
  port                 = local.main_port
  deregistration_delay = 15
  health_check {
    path    = local.health_check.path
    port    = local.health_check.port
    matcher = local.health_check.matcher
  }
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb_target_group" "ingest" {
  name                 = "${var.name}-ingest${local.public_suffix}"
  vpc_id               = var.vpc_id
  target_type          = "ip"
  protocol             = "HTTP"
  port                 = local.ingest_port
  deregistration_delay = 15
  health_check {
    path    = local.health_check.path
    port    = local.health_check.port
    matcher = local.health_check.matcher
  }
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb_listener" "ui_public" {
  count             = local.ui_public
  load_balancer_arn = aws_lb.ui_public[0].arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate_validation.this.certificate_arn
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ui_public[0].arn
  }
}

resource "aws_lb_listener" "ui_internal" {
  count             = local.own_internal
  load_balancer_arn = aws_lb.ui_internal[0].arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate_validation.this.certificate_arn
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ui_internal[0].arn
  }
}

resource "aws_lb_listener" "ingest" {
  count             = local.own_ingest
  load_balancer_arn = aws_lb.ingest[0].arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate_validation.this.certificate_arn
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ingest.arn
  }
}

# On the user's listeners: the module's certificate, and a rule for each name,
# at the priority set, or the next free one when it is null.
resource "aws_lb_listener_certificate" "public" {
  count           = local.reuse_public
  listener_arn    = var.public_listener_arn
  certificate_arn = aws_acm_certificate_validation.this.certificate_arn
}

resource "aws_lb_listener_certificate" "internal" {
  count           = local.reuse_internal
  listener_arn    = var.internal_listener_arn
  certificate_arn = aws_acm_certificate_validation.this.certificate_arn
}

resource "aws_lb_listener_rule" "ingest" {
  count        = local.reuse_public
  listener_arn = var.public_listener_arn
  priority     = var.public_listener_rule_priority
  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ingest.arn
  }
  condition {
    host_header {
      values = [var.ingest_name]
    }
  }
  depends_on = [aws_lb_listener_certificate.public]
}

resource "aws_lb_listener_rule" "ui_internal" {
  count        = local.reuse_internal
  listener_arn = var.internal_listener_arn
  priority     = var.internal_listener_rule_priority
  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ui_internal[0].arn
  }
  condition {
    host_header {
      values = [var.ui_name]
    }
  }
  depends_on = [aws_lb_listener_certificate.internal]
}
