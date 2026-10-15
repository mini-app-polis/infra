# Postgres metrics for the two production databases.
#
# db-poller (mini-app-polis/db-ops) reads each database every five minutes
# and publishes under the MiniAppPolis/Postgres namespace. It runs on Railway
# beside the databases rather than as a Lambda, so it reaches them over
# private networking (db-ops ADR-001); that is why it needs a long-lived key
# rather than a role. Their alarms are below; their dashboard,
# mini-app-polis-data, is in observability.tf.
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

# ── Alarms ───────────────────────────────────────────────────────────────

locals {
  # The Database dimension db-poller publishes each database under (db-ops,
  # poller.Settings.database_urls). A name here that the poller does not
  # publish alarms as unreachable, so the two lists change together.
  postgres_databases = ["kaianolevine", "deejaytools"]

  # WalDirFilling's threshold. Both volumes are 5 GB, and pgBackRest's
  # asynchronous archive queue is capped at about half of that, 2.2 GiB:
  # past the cap it drops WAL and point-in-time recovery has a hole. The
  # alarm fires well short of the cap, and well above a healthy WAL
  # directory, which checkpoints keep near max_wal_size (1 GB by default).
  # Revisit if a volume is resized.
  postgres_wal_dir_alarm_bytes = 1.5 * 1024 * 1024 * 1024
}

# Every database alarm emails here. Only the unreachable alarm treats
# missing data as breaching; the rest leave a silent database to it. Its own topic rather than a cog's, so
# the email says which system it is about; the address is the same one the
# budget and the cogs' alarms use (account.tf). Stays PendingConfirmation,
# delivering nothing, until the emailed link is clicked.
resource "aws_sns_topic" "data_alerts" {
  name = "mini-app-polis-data-alerts"
}

resource "aws_sns_topic_subscription" "data_alerts_email" {
  topic_arn = aws_sns_topic.data_alerts.arn
  protocol  = "email"
  endpoint  = local.alert_email
}

# The poller publishes nothing for a database it cannot reach, so missing
# data is the signal. Three five-minute periods, so one late or skipped
# Railway cron start does not page. Also db-poller's dead-man's switch: if
# the poller stops, every database alarms.
resource "aws_cloudwatch_metric_alarm" "postgres_unreachable" {
  for_each = toset(local.postgres_databases)

  alarm_name          = "postgres-${each.key}-unreachable"
  alarm_description   = "db-poller has published nothing for ${each.key} for 15 minutes: the database is down or unreachable, or db-poller is not running."
  namespace           = "MiniAppPolis/Postgres"
  metric_name         = "Connections"
  statistic           = "SampleCount"
  period              = 300
  evaluation_periods  = 3
  threshold           = 1
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "breaching"

  dimensions = {
    Database = each.key
  }

  alarm_actions = [aws_sns_topic.data_alerts.arn]
  ok_actions    = [aws_sns_topic.data_alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "postgres_connection_utilization" {
  for_each = toset(local.postgres_databases)

  alarm_name          = "postgres-${each.key}-connections-high"
  alarm_description   = "${each.key} has used more than 80% of max_connections for 10 minutes."
  namespace           = "MiniAppPolis/Postgres"
  metric_name         = "ConnectionUtilization"
  statistic           = "Maximum"
  period              = 300
  evaluation_periods  = 2
  threshold           = 80
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    Database = each.key
  }

  alarm_actions = [aws_sns_topic.data_alerts.arn]
  ok_actions    = [aws_sns_topic.data_alerts.arn]
}

# ArchiveFailedCount is cumulative, so the alarm is on its change. Two
# periods in a row, so one failed push that the next retry clears does not
# page; a broken archive fails on every segment.
resource "aws_cloudwatch_metric_alarm" "postgres_archive_failing" {
  for_each = toset(local.postgres_databases)

  alarm_name          = "postgres-${each.key}-archive-failing"
  alarm_description   = "${each.key}'s WAL archive has failed in two periods running: point-in-time recovery is falling behind, and WAL is spooling on the database's volume."
  evaluation_periods  = 2
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  metric_query {
    id          = "failures"
    expression  = "DIFF(failed)"
    label       = "new archive failures"
    return_data = true
  }

  metric_query {
    id = "failed"

    metric {
      namespace   = "MiniAppPolis/Postgres"
      metric_name = "ArchiveFailedCount"
      stat        = "Maximum"
      period      = 300

      dimensions = {
        Database = each.key
      }
    }
  }

  alarm_actions = [aws_sns_topic.data_alerts.arn]
  ok_actions    = [aws_sns_topic.data_alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "postgres_wal_dir_filling" {
  for_each = toset(local.postgres_databases)

  alarm_name          = "postgres-${each.key}-wal-dir-filling"
  alarm_description   = "${each.key}'s WAL directory has been over 1.5 GiB for 15 minutes: the archive is not keeping up, and pgBackRest drops WAL at about 2.2 GiB."
  namespace           = "MiniAppPolis/Postgres"
  metric_name         = "WalDirSize"
  statistic           = "Maximum"
  period              = 300
  evaluation_periods  = 3
  threshold           = local.postgres_wal_dir_alarm_bytes
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    Database = each.key
  }

  alarm_actions = [aws_sns_topic.data_alerts.arn]
  ok_actions    = [aws_sns_topic.data_alerts.arn]
}
