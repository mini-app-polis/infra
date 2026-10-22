# The account's CloudTrail trail: a durable record of who did what.
#
# Without a trail, CloudTrail keeps 90 days of management events in its
# event history and records no data events at all. So nothing can say
# whether anyone read the database dumps: a GetObject on the backup bucket
# is a data event. This trail keeps:
#
#   - every management event, in every region (IAM, SQS, Lambda, ... —
#     the first trail's copy of these is free), and
#   - S3 data events on the backup bucket only: every read and write of a
#     dump, with the caller, its source IP and the object key.
#
# Data events cost per event, so they are scoped to the one bucket whose
# reads matter. db-backup writes a few objects a night and db-drill reads
# one a month; the volume is a rounding error.
#
# The logs land in their own bucket, below. Reading them: README.md,
# "Audit trail".

locals {
  audit_trail_name   = "mini-app-polis-audit"
  audit_trail_bucket = "mini-app-polis-cloudtrail-${data.aws_caller_identity.current.account_id}"

  # Built rather than read from the trail, because the bucket policy that
  # the trail depends on has to name it.
  audit_trail_arn = "arn:aws:cloudtrail:${var.region}:${data.aws_caller_identity.current.account_id}:trail/${local.audit_trail_name}"

  # How long the trail's logs are kept. Long enough to look back past the
  # start of any incident found late; the logs are small.
  audit_trail_days = 365
}

resource "aws_s3_bucket" "audit_trail" {
  bucket = local.audit_trail_bucket

  # Destroying this destroys the record it exists to keep.
  lifecycle {
    prevent_destroy = true
  }
}

# A deleted or overwritten log file stays recoverable as a noncurrent
# version. Log file validation (on the trail) proves whether one changed.
resource "aws_s3_bucket_versioning" "audit_trail" {
  bucket = aws_s3_bucket.audit_trail.id

  versioning_configuration {
    status = "Enabled"
  }
}

# SSE-S3, as for the other buckets: AWS-managed keys, no $1/month CMK.
resource "aws_s3_bucket_server_side_encryption_configuration" "audit_trail" {
  bucket = aws_s3_bucket.audit_trail.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "audit_trail" {
  bucket = aws_s3_bucket.audit_trail.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ACLs off; access is IAM and the bucket policy only.
resource "aws_s3_bucket_ownership_controls" "audit_trail" {
  bucket = aws_s3_bucket.audit_trail.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

data "aws_iam_policy_document" "audit_trail_bucket" {
  # Refuse anything not over TLS.
  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.audit_trail.arn,
      "${aws_s3_bucket.audit_trail.arn}/*",
    ]

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

  # CloudTrail's documented bucket policy, held to this one trail by
  # aws:SourceArn so no other account's trail can write here.
  statement {
    sid       = "CloudTrailAclCheck"
    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.audit_trail.arn]

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [local.audit_trail_arn]
    }
  }

  statement {
    sid       = "CloudTrailWrite"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.audit_trail.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"]

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [local.audit_trail_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
  }
}

resource "aws_s3_bucket_policy" "audit_trail" {
  bucket = aws_s3_bucket.audit_trail.id
  policy = data.aws_iam_policy_document.audit_trail_bucket.json

  # The public access block must exist first, or S3 can evaluate the policy
  # against a bucket that has not yet opted out of public policies.
  depends_on = [aws_s3_bucket_public_access_block.audit_trail]
}

resource "aws_s3_bucket_lifecycle_configuration" "audit_trail" {
  bucket = aws_s3_bucket.audit_trail.id

  rule {
    id     = "expire-logs"
    status = "Enabled"

    filter {}

    expiration {
      days = local.audit_trail_days
    }

    noncurrent_version_expiration {
      noncurrent_days = local.audit_trail_days
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  depends_on = [aws_s3_bucket_versioning.audit_trail]
}

resource "aws_cloudtrail" "audit" {
  name           = local.audit_trail_name
  s3_bucket_name = aws_s3_bucket.audit_trail.id

  # Every region, so activity in a region the fleet never uses — where an
  # intruder would go — is recorded too. Global services (IAM, STS) with it.
  is_multi_region_trail         = true
  include_global_service_events = true

  # A signed digest per hour, so a changed or deleted log file is provable.
  enable_log_file_validation = true

  advanced_event_selector {
    name = "Management events"

    field_selector {
      field  = "eventCategory"
      equals = ["Management"]
    }
  }

  advanced_event_selector {
    name = "Database backup reads and writes"

    field_selector {
      field  = "eventCategory"
      equals = ["Data"]
    }

    field_selector {
      field  = "resources.type"
      equals = ["AWS::S3::Object"]
    }

    field_selector {
      field       = "resources.ARN"
      starts_with = ["${aws_s3_bucket.db_backups.arn}/"]
    }
  }

  depends_on = [aws_s3_bucket_policy.audit_trail]
}
