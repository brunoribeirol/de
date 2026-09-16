# =============================================================================
# Remote state backend — one S3 bucket per owner, plus the class-wide DynamoDB
# lock table (read only, created by whoever owns it).
#
# This stack is deliberately separate from the lab stacks: `terraform destroy`
# in labs/NN must never be able to take the state bucket down with it.
# =============================================================================

locals {
  bucket_name = "eda-tfstate-${var.grupo}"
}

resource "aws_s3_bucket" "tfstate" {
  bucket = local.bucket_name

  # Losing this bucket means losing the state of every stack that points at it:
  # the resources keep existing in AWS while Terraform believes it owns nothing.
  lifecycle {
    prevent_destroy = true
  }
}

# Versioning is the recovery path for a corrupted or truncated state file: the
# previous object version can be restored.
resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Versioning keeps every superseded state file forever unless told otherwise.
# 90 days is well past any realistic rollback and keeps storage near zero.
resource "aws_s3_bucket_lifecycle_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  rule {
    id     = "expire-noncurrent-state-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = var.noncurrent_version_expiration_days
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  depends_on = [aws_s3_bucket_versioning.tfstate]
}

# State files carry resource IDs and, depending on the provider, sensitive
# attribute values. Refusing plaintext transport is the cheapest guardrail.
data "aws_iam_policy_document" "tfstate" {
  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions = ["s3:*"]

    resources = [
      aws_s3_bucket.tfstate.arn,
      "${aws_s3_bucket.tfstate.arn}/*",
    ]

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

  # The public access block must be in place first, otherwise attaching a policy
  # to a bucket that still allows public policies is briefly unsafe.
  depends_on = [aws_s3_bucket_public_access_block.tfstate]
}

# The lock table belongs to the class, not to this stack: reading it asserts the
# dependency without claiming ownership of a resource someone else created.
data "aws_dynamodb_table" "lock" {
  name = var.lock_table_name
}
