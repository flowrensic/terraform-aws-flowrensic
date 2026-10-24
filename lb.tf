locals {
  health_check = {
    path    = "/readyz"
    port    = tostring(local.main_port)
    matcher = "200"
  }
}

resource "aws_lb" "ui_public" {
  name               = "${var.name}-ui"
  load_balancer_type = "application"
  internal           = false
  subnets            = var.public_subnet_ids
  security_groups    = [aws_security_group.ui_public.id]
}

resource "aws_lb" "ui_internal" {
  count              = local.internal
  name               = "${var.name}-ui-int"
  load_balancer_type = "application"
  internal           = true
  subnets            = var.public_subnet_ids
  security_groups    = [aws_security_group.ui_internal[0].id]
}

resource "aws_lb" "ingest" {
  name               = "${var.name}-ingest"
  load_balancer_type = "application"
  internal           = false
  subnets            = var.public_subnet_ids
  security_groups    = [aws_security_group.ingest.id]
}

resource "aws_lb_target_group" "ui_public" {
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
}

resource "aws_lb_target_group" "ui_internal" {
  count                = local.internal
  name                 = "${var.name}-ui-int"
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
}

resource "aws_lb_target_group" "ingest" {
  name                 = "${var.name}-ingest"
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
}

resource "aws_lb_listener" "ui_public" {
  load_balancer_arn = aws_lb.ui_public.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate_validation.this.certificate_arn
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ui_public.arn
  }
}

resource "aws_lb_listener" "ui_internal" {
  count             = local.internal
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
  load_balancer_arn = aws_lb.ingest.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate_validation.this.certificate_arn
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ingest.arn
  }
}
