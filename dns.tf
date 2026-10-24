data "aws_route53_zone" "public" {
  name         = var.dns_zone
  private_zone = false
}

resource "aws_acm_certificate" "this" {
  domain_name               = var.ui_name
  subject_alternative_names = [var.ingest_name, local.grafana_name]
  validation_method         = "DNS"
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "validation" {
  for_each = {
    for option in aws_acm_certificate.this.domain_validation_options : option.domain_name => option
  }
  zone_id         = data.aws_route53_zone.public.zone_id
  name            = each.value.resource_record_name
  type            = each.value.resource_record_type
  records         = [each.value.resource_record_value]
  ttl             = 60
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "this" {
  certificate_arn         = aws_acm_certificate.this.arn
  validation_record_fqdns = [for record in aws_route53_record.validation : record.fqdn]
}

resource "aws_route53_record" "ui_public" {
  zone_id = data.aws_route53_zone.public.zone_id
  name    = var.ui_name
  type    = "A"
  alias {
    name                   = aws_lb.ui_public.dns_name
    zone_id                = aws_lb.ui_public.zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "ingest" {
  zone_id = data.aws_route53_zone.public.zone_id
  name    = var.ingest_name
  type    = "A"
  alias {
    name                   = aws_lb.ingest.dns_name
    zone_id                = aws_lb.ingest.zone_id
    evaluate_target_health = false
  }
}

# Inside the VPC the UI name points at the internal load balancer, so a server
# in an allowed security group reaches it by the same name.
resource "aws_route53_zone" "ui_private" {
  count         = local.internal
  name          = var.ui_name
  force_destroy = true
  vpc {
    vpc_id = var.vpc_id
  }
}

resource "aws_route53_record" "ui_private" {
  count   = local.internal
  zone_id = aws_route53_zone.ui_private[0].zone_id
  name    = var.ui_name
  type    = "A"
  alias {
    name                   = aws_lb.ui_internal[0].dns_name
    zone_id                = aws_lb.ui_internal[0].zone_id
    evaluate_target_health = false
  }
}
