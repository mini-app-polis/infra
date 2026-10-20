# Alarms on the request metrics each API publishes through common-python-
# utils' RequestMetricsMiddleware (MiniAppPolis/Api, Service dimension). One
# pair per API in dashboard_apis (observability.tf), so an API added there
# is alarmed as well as drawn.
#
# Both alarm on sustained trouble, not on a single bad minute. Single slow
# requests are what the middleware's "slow request" log line is for; these
# fire when the service as a whole is degraded. Thresholds sit well above
# the normal levels on each API's latency and 5xx-rate panels on
# mini-app-polis-services; revisit them if those levels move.

locals {
  # p95 above this for every period in the window. Both APIs' normal p95 is
  # well under a second; this is a service that has stopped
  # answering promptly, not one that had a slow request.
  api_p95_alarm_ms      = 2000
  api_p95_alarm_periods = 3

  # Percent of requests answered 5xx, in consecutive periods. A rate rather
  # than a count, so a quiet API and a busy one mean the same thing by it.
  api_5xx_alarm_percent = 1
  api_5xx_alarm_periods = 2
}

# Its own topic, so the email says which system it is about — the same
# reasoning as data_alerts. Stays PendingConfirmation, delivering nothing,
# until the emailed link is clicked.
resource "aws_sns_topic" "api_alerts" {
  name = "mini-app-polis-api-alerts"
}

resource "aws_sns_topic_subscription" "api_alerts_email" {
  topic_arn = aws_sns_topic.api_alerts.arn
  protocol  = "email"
  endpoint  = local.alert_email
}

resource "aws_cloudwatch_metric_alarm" "api_p95_latency" {
  for_each = toset(local.dashboard_apis)

  alarm_name          = "${each.key}-p95-latency-high"
  alarm_description   = "${each.key} p95 latency has been above ${local.api_p95_alarm_ms} ms for ${local.api_p95_alarm_periods * 5} minutes. Search its Deploy Logs for \"slow request\" to see which routes."
  namespace           = "MiniAppPolis/Api"
  metric_name         = "Latency"
  extended_statistic  = "p95"
  period              = 300
  evaluation_periods  = local.api_p95_alarm_periods
  threshold           = local.api_p95_alarm_ms
  comparison_operator = "GreaterThanThreshold"
  # No requests is not slow requests. An API that stops answering entirely
  # is the deploy smoke test's and Railway's restart policy's to catch.
  treat_missing_data = "notBreaching"

  dimensions = {
    Service = each.key
  }

  alarm_actions = [aws_sns_topic.api_alerts.arn]
  ok_actions    = [aws_sns_topic.api_alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "api_5xx_rate" {
  for_each = toset(local.dashboard_apis)

  alarm_name          = "${each.key}-5xx-rate-high"
  alarm_description   = "${each.key} has answered more than ${local.api_5xx_alarm_percent}% of requests with a 5xx for ${local.api_5xx_alarm_periods * 5} minutes. Its errors Discord channel and Sentry have the detail."
  evaluation_periods  = local.api_5xx_alarm_periods
  threshold           = local.api_5xx_alarm_percent
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  metric_query {
    id          = "rate"
    expression  = "100 * errors / requests"
    label       = "5xx %"
    return_data = true
  }

  metric_query {
    id = "errors"
    metric {
      namespace   = "MiniAppPolis/Api"
      metric_name = "Errors5xx"
      stat        = "Sum"
      period      = 300
      dimensions = {
        Service = each.key
      }
    }
  }

  metric_query {
    id = "requests"
    metric {
      namespace   = "MiniAppPolis/Api"
      metric_name = "Latency"
      stat        = "SampleCount"
      period      = 300
      dimensions = {
        Service = each.key
      }
    }
  }

  alarm_actions = [aws_sns_topic.api_alerts.arn]
  ok_actions    = [aws_sns_topic.api_alerts.arn]
}
