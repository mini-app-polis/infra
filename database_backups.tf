# Off-platform backups of the two production Postgres databases.
#
# Railway's point-in-time recovery covers a bad migration or a dropped
# table, but it lives with Railway: its archive is a Railway bucket, and
# wiping a volume or losing the project takes the backups with it. This
# bucket is the copy for when Railway itself is the problem, and the exit
# path if the databases ever leave. db-backup (mini-app-polis/db-ops) writes
# a pg_dump of each database here nightly; db-drill restores from it.
#
# Object keys, which the lifecycle below depends on:
#
#   daily/<database>/<UTC timestamp>.dump     every run
#   monthly/<database>/<UTC timestamp>.dump   the first run of each month
#
# The two IAM users' access keys are minted by hand straight into Doppler
# (`aws iam create-access-key --user-name db-backup-writer`, and the same
# for db-backup-reader), never by Terraform, so no secret is in state or a
# plan. There is no OIDC path from Railway, so these are long-lived keys.

locals {
  db_backups_bucket = "mini-app-polis-db-backups-${data.aws_caller_identity.current.account_id}"

  # How long a dump is kept. These numbers are also how long a deejaytools
  # user's deleted data can survive in a backup, which the data-erasure
  # path has to state.
  db_backups_daily_days   = 30
  db_backups_monthly_days = 90

  # Governance-mode lock on every object version for its first week: not
  # even the writer's key, or a mistake with an admin key that does not
  # deliberately bypass governance, can delete or overwrite a fresh dump.
  # Governance rather than compliance because compliance cannot be
  # shortened even by root, and a deejaytools user's erasure request must
  # be able to reach the backups.
  db_backups_lock_days = 7
}

resource "aws_s3_bucket" "db_backups" {
  bucket = local.db_backups_bucket

  # Object Lock can only be turned on when a bucket is created.
  object_lock_enabled = true

  lifecycle {
    prevent_destroy = true
  }
}

# Required by Object Lock, and what makes an overwritten or deleted dump
# recoverable as a noncurrent version.
resource "aws_s3_bucket_versioning" "db_backups" {
  bucket = aws_s3_bucket.db_backups.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_object_lock_configuration" "db_backups" {
  bucket = aws_s3_bucket.db_backups.id

  rule {
    default_retention {
      mode = "GOVERNANCE"
      days = local.db_backups_lock_days
    }
  }

  depends_on = [aws_s3_bucket_versioning.db_backups]
}

# SSE-S3, as for the state bucket: AWS-managed keys, no $1/month CMK. The
# boundary that matters is who can read the bucket, and that is the reader
# user and the account admin.
resource "aws_s3_bucket_server_side_encryption_configuration" "db_backups" {
  bucket = aws_s3_bucket.db_backups.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "db_backups" {
  bucket = aws_s3_bucket.db_backups.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ACLs off; access is IAM and the bucket policy only.
resource "aws_s3_bucket_ownership_controls" "db_backups" {
  bucket = aws_s3_bucket.db_backups.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

data "aws_iam_policy_document" "db_backups_bucket" {
  # Refuse anything not over TLS.
  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.db_backups.arn,
      "${aws_s3_bucket.db_backups.arn}/*",
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
}

resource "aws_s3_bucket_policy" "db_backups" {
  bucket = aws_s3_bucket.db_backups.id
  policy = data.aws_iam_policy_document.db_backups_bucket.json

  # The public access block must exist first, or S3 can evaluate the policy
  # against a bucket that has not yet opted out of public policies.
  depends_on = [aws_s3_bucket_public_access_block.db_backups]
}

# Retention by prefix. A version under lock cannot be expired until its lock
# ends, so every expiry here is longer than the lock.
resource "aws_s3_bucket_lifecycle_configuration" "db_backups" {
  bucket = aws_s3_bucket.db_backups.id

  rule {
    id     = "expire-dailies"
    status = "Enabled"

    filter {
      prefix = "daily/"
    }

    expiration {
      days = local.db_backups_daily_days
    }
  }

  rule {
    id     = "expire-monthlies"
    status = "Enabled"

    filter {
      prefix = "monthly/"
    }

    expiration {
      days = local.db_backups_monthly_days
    }
  }

  # Applies to the whole bucket: an expired or overwritten dump becomes a
  # noncurrent version, kept one day past its lock and then removed, so an
  # expiry above actually frees the space and a deleted dump does not live
  # on as a version nobody sees.
  rule {
    id     = "expire-noncurrent"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = local.db_backups_lock_days + 1
    }

    expiration {
      expired_object_delete_marker = true
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  depends_on = [aws_s3_bucket_versioning.db_backups]
}

# ── The writer: db-backup ────────────────────────────────────────────────

# PutObject and nothing else. A leaked key can add dumps; it cannot read,
# list, overwrite in place (versioning keeps the original) or delete one.
resource "aws_iam_user" "db_backup_writer" {
  name = "db-backup-writer"

  # Replacing the user invalidates the key in Doppler.
  lifecycle {
    prevent_destroy = true
  }
}

data "aws_iam_policy_document" "db_backup_writer" {
  statement {
    actions = ["s3:PutObject"]
    resources = [
      "${aws_s3_bucket.db_backups.arn}/daily/*",
      "${aws_s3_bucket.db_backups.arn}/monthly/*",
    ]
  }
}

resource "aws_iam_user_policy" "db_backup_writer" {
  name   = "db-backup-writer-put"
  user   = aws_iam_user.db_backup_writer.name
  policy = data.aws_iam_policy_document.db_backup_writer.json
}

# ── The reader: db-drill ─────────────────────────────────────────────────

# Get and List only: enough to find the newest dump and restore it, and
# nothing that changes the bucket.
resource "aws_iam_user" "db_backup_reader" {
  name = "db-backup-reader"

  lifecycle {
    prevent_destroy = true
  }
}

data "aws_iam_policy_document" "db_backup_reader" {
  statement {
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.db_backups.arn]
  }

  statement {
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.db_backups.arn}/*"]
  }
}

resource "aws_iam_user_policy" "db_backup_reader" {
  name   = "db-backup-reader-get"
  user   = aws_iam_user.db_backup_reader.name
  policy = data.aws_iam_policy_document.db_backup_reader.json
}
