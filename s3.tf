resource "aws_s3_bucket" "histories" {
  bucket        = "${var.name}-histories-${local.account}-${var.region}"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "histories" {
  bucket                  = aws_s3_bucket.histories.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "histories" {
  bucket = aws_s3_bucket.histories.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_ownership_controls" "histories" {
  bucket = aws_s3_bucket.histories.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

data "aws_iam_policy_document" "histories" {
  statement {
    sid       = "NoCallWithoutTls"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.histories.arn, "${aws_s3_bucket.histories.arn}/*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }

  statement {
    sid       = "OnlyTheServerReadsAndWrites"
    effect    = "Deny"
    actions   = ["s3:GetObject", "s3:PutObject"]
    resources = ["${aws_s3_bucket.histories.arn}/*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "ArnNotEquals"
      variable = "aws:PrincipalArn"
      values   = [aws_iam_role.task.arn]
    }
  }

  statement {
    sid       = "OnlyThroughTheGatewayEndpoint"
    effect    = "Deny"
    actions   = ["s3:GetObject", "s3:PutObject"]
    resources = ["${aws_s3_bucket.histories.arn}/*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "StringNotEquals"
      variable = "aws:SourceVpce"
      values   = [local.s3_endpoint_id]
    }
  }
}

resource "aws_s3_bucket_policy" "histories" {
  bucket     = aws_s3_bucket.histories.id
  policy     = data.aws_iam_policy_document.histories.json
  depends_on = [aws_s3_bucket_public_access_block.histories]
}
