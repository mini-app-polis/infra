# Postgres metrics for the two production databases.
#
# db-poller (mini-app-polis/db-ops) reads each database every five minutes
# and publishes under the MiniAppPolis/Postgres namespace. It runs on Railway
# beside the databases rather than as a Lambda, so it reaches them over
# private networking (db-ops ADR-001); that is why it needs a long-lived key
# rather than a role. The dashboard and alarms for these metrics are MINI-61.
#
# The key is minted by hand straight into Doppler
# (`aws iam create-access-key --user-name db-poller`), never by Terraform, so
# no secret is in state or a plan.

resource "aws_iam_user" "db_poller" {
  name = "db-poller"

  # Replacing the user invalidates the key in Doppler.
  lifecycle {
    prevent_destroy = true
  }
}

data "aws_iam_policy_document" "db_poller" {
  # PutMetricData has no resource-level permissions, so the namespace
  # condition is the whole boundary: this key can write Postgres metrics and
  # cannot forge an API's or a cog's — the same boundary the API's producer
  # key has on MiniAppPolis/Api (account.tf).
  statement {
    actions   = ["cloudwatch:PutMetricData"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "cloudwatch:namespace"
      values   = ["MiniAppPolis/Postgres"]
    }
  }
}

resource "aws_iam_user_policy" "db_poller" {
  name   = "db-poller-put-metrics"
  user   = aws_iam_user.db_poller.name
  policy = data.aws_iam_policy_document.db_poller.json
}

output "db_poller_user_name" {
  description = "Mint its access key by hand, straight into Doppler."
  value       = aws_iam_user.db_poller.name
}
