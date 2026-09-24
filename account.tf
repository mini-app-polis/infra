# Resources there is one of per AWS account, shared by every cog.
#
# These lived in evaluator-cog's state, behind create_* flags every other
# cog set to false. Their names still say "evaluator" because renaming a
# budget or an IAM user replaces it — and replacing the producer user
# invalidates the access key the API enqueues with.

data "aws_caller_identity" "current" {}

# Where the budget and every cog's dead-letter alarm go: the ecosystem's
# contact address, CONTACT_TO_EMAIL in Doppler, read via Parameter Store
# rather than committed — this repository is public, and a tfvars file on a
# workstation is exactly what this repository exists to not need. Changing
# that secret moves these alerts too, and each SNS subscription then needs
# confirming again from the new inbox.
data "aws_ssm_parameter" "alert_email" {
  name = "/mini-app-polis/prd/CONTACT_TO_EMAIL"
}

locals {
  alert_email = data.aws_ssm_parameter.alert_email.value
}

# ── Budget ───────────────────────────────────────────────────────────────

resource "aws_budgets_budget" "monthly" {
  name         = "evaluator-monthly"
  budget_type  = "COST"
  limit_amount = tostring(var.budget_limit_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  # Actual spend, not forecast: a forecast on a near-zero baseline cries
  # wolf on the first of every month.
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 50
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [local.alert_email]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [local.alert_email]
  }
}

# ── GitHub OIDC ──────────────────────────────────────────────────────────

# How every cog's CI deploys without a long-lived key. One per account.
resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]

  # AWS no longer validates these for this issuer but the argument is
  # required. Both of GitHub's published values.
  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd",
  ]
}

# ── The API's sending identity ───────────────────────────────────────────

# api-kaianolevine-com is the fleet's only producer. One identity for one
# API; its access key is minted by hand straight into Doppler
# (`aws iam create-access-key --user-name evaluator-producer`), never by
# Terraform. There is no OIDC path from Railway, so this is the account's
# one long-lived credential — the thing most worth a rotation reminder.
resource "aws_iam_user" "producer" {
  name = "evaluator-producer"

  lifecycle {
    prevent_destroy = true
  }
}

data "aws_iam_policy_document" "producer" {
  # Send, and nothing else, to any `*-jobs` queue in this account. A new
  # cog's queue is covered the moment it exists. The key can cause work to
  # happen; it cannot read, drain or dead-letter anything.
  statement {
    actions   = ["sqs:SendMessage"]
    resources = ["arn:aws:sqs:${var.region}:${data.aws_caller_identity.current.account_id}:*-jobs"]
  }
}

resource "aws_iam_user_policy" "producer" {
  # Renaming replaces it, and Terraform replaces an inline policy by delete
  # then create — a window where the API cannot enqueue.
  name   = "evaluator-producer-send"
  user   = aws_iam_user.producer.name
  policy = data.aws_iam_policy_document.producer.json
}
