# The fleet on one screen: every cog's function and queues, from metrics
# AWS publishes on its own. Nothing here is a custom metric, so it costs
# nothing — dashboards are free up to three per account at 50 metrics each,
# and this one references about 25.
#
# Built from the cog modules, so a cog added to cogs.tf and to the maps
# below gets its row. The API and Postgres rows arrive with their custom
# metrics (the Fleet Metrics Plan, steps 2 and 3).

locals {
  # Queue consumers: function, work queue and dead-letter queue.
  dashboard_queue_cogs = {
    evaluator     = module.evaluator
    deejay        = module.deejay
    transcription = module.transcription
  }

  # Scheduled: function only.
  dashboard_scheduled_cogs = {
    watcher = module.watcher
  }

  dashboard_row_height = 6
  dashboard_header     = 2

  queue_cog_rows = [
    for i, name in sort(keys(local.dashboard_queue_cogs)) : [
      {
        type   = "metric"
        x      = 0
        y      = local.dashboard_header + i * local.dashboard_row_height
        width  = 6
        height = local.dashboard_row_height
        properties = {
          title  = "${name}: invocations"
          region = var.region
          view   = "timeSeries"
          stat   = "Sum"
          period = 3600
          metrics = [
            ["AWS/Lambda", "Invocations", "FunctionName", local.dashboard_queue_cogs[name].function_name],
            [".", "Errors", ".", ".", { color = "#d62728" }],
            [".", "Throttles", ".", ".", { color = "#ff7f0e" }],
          ]
        }
      },
      {
        type   = "metric"
        x      = 6
        y      = local.dashboard_header + i * local.dashboard_row_height
        width  = 6
        height = local.dashboard_row_height
        properties = {
          title  = "${name}: duration (ms)"
          region = var.region
          view   = "timeSeries"
          period = 3600
          metrics = [
            ["AWS/Lambda", "Duration", "FunctionName", local.dashboard_queue_cogs[name].function_name, { stat = "p50", label = "p50" }],
            ["...", { stat = "p95", label = "p95" }],
            ["...", { stat = "p99", label = "p99" }],
          ]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = local.dashboard_header + i * local.dashboard_row_height
        width  = 6
        height = local.dashboard_row_height
        properties = {
          title  = "${name}: queue"
          region = var.region
          view   = "timeSeries"
          stat   = "Maximum"
          period = 300
          metrics = [
            ["AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", local.dashboard_queue_cogs[name].queue_name, { label = "waiting" }],
            [".", "ApproximateNumberOfMessagesNotVisible", ".", ".", { label = "in flight" }],
            [".", "ApproximateAgeOfOldestMessage", ".", ".", { label = "oldest (s)", yAxis = "right" }],
          ]
          annotations = {
            # The queue-stalled alarm's threshold.
            horizontal = [{ label = "stalled", value = local.dashboard_queue_cogs[name].max_in_flight_seconds, yAxis = "right" }]
          }
        }
      },
      {
        type   = "metric"
        x      = 18
        y      = local.dashboard_header + i * local.dashboard_row_height
        width  = 6
        height = local.dashboard_row_height
        properties = {
          title  = "${name}: dead-letter queue"
          region = var.region
          view   = "timeSeries"
          stat   = "Maximum"
          period = 300
          metrics = [
            ["AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", local.dashboard_queue_cogs[name].dlq_name, { label = "dead-lettered", color = "#d62728" }],
          ]
        }
      },
    ]
  ]

  scheduled_rows_top = local.dashboard_header + length(local.dashboard_queue_cogs) * local.dashboard_row_height

  scheduled_cog_rows = [
    for i, name in sort(keys(local.dashboard_scheduled_cogs)) : [
      {
        type   = "metric"
        x      = 0
        y      = local.scheduled_rows_top + i * local.dashboard_row_height
        width  = 6
        height = local.dashboard_row_height
        properties = {
          title  = "${name}: ticks"
          region = var.region
          view   = "timeSeries"
          stat   = "Sum"
          period = 3600
          metrics = [
            ["AWS/Lambda", "Invocations", "FunctionName", local.dashboard_scheduled_cogs[name].function_name],
            [".", "Errors", ".", ".", { color = "#d62728" }],
            [".", "Throttles", ".", ".", { color = "#ff7f0e" }],
          ]
        }
      },
      {
        type   = "metric"
        x      = 6
        y      = local.scheduled_rows_top + i * local.dashboard_row_height
        width  = 6
        height = local.dashboard_row_height
        properties = {
          title  = "${name}: duration (ms)"
          region = var.region
          view   = "timeSeries"
          period = 3600
          metrics = [
            ["AWS/Lambda", "Duration", "FunctionName", local.dashboard_scheduled_cogs[name].function_name, { stat = "p50", label = "p50" }],
            ["...", { stat = "p95", label = "p95" }],
            ["...", { stat = "p99", label = "p99" }],
          ]
        }
      },
    ]
  ]
}

resource "aws_cloudwatch_dashboard" "services" {
  dashboard_name = "mini-app-polis-services"

  dashboard_body = jsonencode({
    widgets = concat(
      [{
        type   = "text"
        x      = 0
        y      = 0
        width  = 24
        height = local.dashboard_header
        properties = {
          markdown = "## mini-app-polis services\nOne row per cog. Invocations and duration are hourly, since the cogs run in bursts; queues are 5-minute, and the queue graph marks where the stalled alarm fires. Defined in mini-app-polis/infra `observability.tf`."
        }
      }],
      flatten(local.queue_cog_rows),
      flatten(local.scheduled_cog_rows),
    )
  })
}

output "dashboard_url" {
  description = "The fleet dashboard in the CloudWatch console."
  value       = "https://${var.region}.console.aws.amazon.com/cloudwatch/home?region=${var.region}#dashboards/dashboard/${aws_cloudwatch_dashboard.services.dashboard_name}"
}
