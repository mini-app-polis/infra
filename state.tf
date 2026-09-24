# The bucket that holds this repository's own state.
#
# Created once with the AWS CLI and adopted by an import block on the first
# apply (README.md, "Bootstrap"), so Terraform has owned its configuration
# from the start and no local state file ever existed.

resource "aws_s3_bucket" "tfstate" {
  bucket = "mini-app-polis-tfstate-400200465748"

  # Destroying this orphans every resource in the account from Terraform.
  lifecycle {
    prevent_destroy = true
  }
}

# Every write keeps the previous version. This is the backup: a bad apply or
# a corrupted state is rolled back by restoring an earlier object version.
resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  versioning_configuration {
    status = "Enabled"
  }
}

# SSE-S3, not a customer-managed KMS key. State holds no secrets once they
# move to Parameter Store, and a CMK would add ~$1/month for nothing.
resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ACLs off; access is IAM and the bucket policy only.
resource "aws_s3_bucket_ownership_controls" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

data "aws_iam_policy_document" "tfstate" {
  # Refuse anything not over TLS.
  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.tfstate.arn,
      "${aws_s3_bucket.tfstate.arn}/*",
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

resource "aws_s3_bucket_policy" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  policy = data.aws_iam_policy_document.tfstate.json

  # The public access block must exist first, or S3 can evaluate the policy
  # against a bucket that has not yet opted out of public policies.
  depends_on = [aws_s3_bucket_public_access_block.tfstate]
}

# Versioning keeps every state write, and the lock file (`infra.tfstate.tflock`)
# leaves a delete marker each time it is released. Without expiry both grow
# forever. Ninety days of history, and never fewer than the ten most recent
# versions however old they are.
resource "aws_s3_bucket_lifecycle_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  rule {
    id     = "expire-old-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days           = 90
      newer_noncurrent_versions = 10
    }

    expiration {
      expired_object_delete_marker = true
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  depends_on = [aws_s3_bucket_versioning.tfstate]
}
