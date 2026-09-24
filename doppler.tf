# The role Doppler assumes to sync each Lambda cog's secrets into SSM
# Parameter Store.
#
# Doppler is the one place secrets are edited. Its AWS Parameter Store
# integration writes each synced config under a path prefix —
# /mini-app-polis/<cog>/ — and each worker reads only its own prefix at cold
# start. Nothing secret passes through Terraform, so nothing secret is in
# state or in a plan.
#
# The Doppler free plan allows five synced configs. One per Lambda cog in
# production; dev runs locally with `doppler run` and is never synced.

locals {
  # Everything the fleet's workers read lives under this prefix.
  ssm_prefix = "mini-app-polis"
}

data "aws_iam_policy_document" "doppler_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    # Doppler's integration user specifically, not its whole account — the
    # tighter of the two principals Doppler documents.
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::299900769157:user/doppler-integration-operator"]
    }

    # Without the external ID, any Doppler customer who learned this role's
    # ARN could point their own sync at it (the confused-deputy problem).
    condition {
      test     = "StringEquals"
      variable = "sts:ExternalId"
      values   = [var.doppler_workplace_id]
    }
  }
}

resource "aws_iam_role" "doppler_sync" {
  name               = "doppler-parameter-store-sync"
  assume_role_policy = data.aws_iam_policy_document.doppler_assume.json
}

data "aws_iam_policy_document" "doppler_sync" {
  # Doppler's documented action list, scoped to the fleet's prefix rather
  # than "*". It can write, tag and delete parameters under
  # /mini-app-polis/ and nothing else in the account.
  #
  # No KMS actions: parameters are SecureStrings under the AWS-managed
  # aws/ssm key, which any principal in the account may use through SSM.
  statement {
    actions = [
      "ssm:PutParameter",
      "ssm:LabelParameterVersion",
      "ssm:DeleteParameter",
      "ssm:DeleteParameters",
      "ssm:GetParameter",
      "ssm:GetParameters",
      "ssm:GetParametersByPath",
      "ssm:GetParameterHistory",
      "ssm:AddTagsToResource",
      "ssm:RemoveTagsFromResource",
    ]
    resources = [
      "arn:aws:ssm:${var.region}:${data.aws_caller_identity.current.account_id}:parameter/${local.ssm_prefix}/*",
    ]
  }
}

resource "aws_iam_role_policy" "doppler_sync" {
  name   = "doppler-parameter-store-sync"
  role   = aws_iam_role.doppler_sync.id
  policy = data.aws_iam_policy_document.doppler_sync.json
}
