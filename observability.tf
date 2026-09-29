# The fleet on one screen: each API's requests, then every cog's function
# and queues. The cog rows are metrics AWS publishes on its own, at no
# cost. The API rows are custom metrics published by common-python-utils'
# request_metrics middleware (MiniAppPolis/Api) and billed per metric.
# Dashboards are free up to three per account at 50 metrics each; this one
# references about 30.
#
# Built from the cog modules, so a cog added to cogs.tf and to the maps
# below gets its row; an API gets its row by being added to
# dashboard_apis. Postgres gets its own dashboard with its poller (the
# Fleet Metrics Plan, step 3).

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

  # The Service dimension each API publishes under.
  dashboard_apis = ["api-kaianolevine-com"]

  # Per API, the routes it gives their own Latency series (the `routes`
  # argument to RequestMetricsMiddleware). Must match what the API
  # publishes: a route listed here and not there draws an empty line.
  dashboard_api_routes = {
    "api-kaianolevine-com" = ["/v1/standards/catalog", "/v1/evaluations"]
  }

  dashboard_row_height = 6
  dashboard_header     = 2

  api_rows = [
    for i, service in local.dashboard_apis : [
      {
        type   = "metric"
        x      = 0
        y      = local.dashboard_header + i * local.dashboard_row_height
        width  = 6
        height = local.dashboard_row_height
        properties = {
          title  = "${service}: latency (ms)"
          region = var.region
          view   = "timeSeries"
          period = 300
          metrics = [
            ["MiniAppPolis/Api", "Latency", "Service", service, { stat = "p50", label = "p50" }],
            ["...", { stat = "p95", label = "p95" }],
            ["...", { stat = "p99", label = "p99" }],
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
          title  = "${service}: requests"
          region = var.region
          view   = "timeSeries"
          period = 300
          metrics = [
            ["MiniAppPolis/Api", "Latency", "Service", service, { stat = "SampleCount", label = "requests" }],
            [".", "Errors4xx", ".", ".", { stat = "Sum", label = "4xx", color = "#ff7f0e" }],
            [".", "Errors5xx", ".", ".", { stat = "Sum", label = "5xx", color = "#d62728" }],
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
          title  = "${service}: 5xx rate (%)"
          region = var.region
          view   = "timeSeries"
          period = 300
          metrics = [
            [{ expression = "100 * errors / requests", label = "5xx %", id = "rate" }],
            ["MiniAppPolis/Api", "Errors5xx", "Service", service, { stat = "Sum", id = "errors", visible = false }],
            [".", "Latency", ".", ".", { stat = "SampleCount", id = "requests", visible = false }],
          ]
        }
      },
      {
        type   = "metric"
        x      = 18
        y      = local.dashboard_header + i * local.dashboard_row_height
        width  = 6
        height = local.dashboard_row_height
        properties = {
          title  = "${service}: p95 by route (ms)"
          region = var.region
          view   = "timeSeries"
          period = 300
          stat   = "p95"
          metrics = [
            for route in lookup(local.dashboard_api_routes, service, []) :
            ["MiniAppPolis/Api", "Latency", "Service", service, "Route", route, { label = route }]
          ]
        }
      },
    ]
  ]

  cog_rows_top = local.dashboard_header + length(local.dashboard_apis) * local.dashboard_row_height

  queue_cog_rows = [
    for i, name in sort(keys(local.dashboard_queue_cogs)) : [
      {
        type   = "metric"
        x      = 0
        y      = local.cog_rows_top + i * local.dashboard_row_height
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
        y      = local.cog_rows_top + i * local.dashboard_row_height
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
        y      = local.cog_rows_top + i * local.dashboard_row_height
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
        y      = local.cog_rows_top + i * local.dashboard_row_height
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

  scheduled_rows_top = local.cog_rows_top + length(local.dashboard_queue_cogs) * local.dashboard_row_height

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
          markdown = "## mini-app-polis services\nOne row per API, then one per cog. Invocations and duration are hourly, since the cogs run in bursts; queues are 5-minute, and the queue graph marks where the stalled alarm fires. Defined in mini-app-polis/infra `observability.tf`."
        }
      }],
      flatten(local.api_rows),
      flatten(local.queue_cog_rows),
      flatten(local.scheduled_cog_rows),
    )
  })
}

output "dashboard_url" {
  description = "The fleet dashboard in the CloudWatch console."
  value       = "https://${var.region}.console.aws.amazon.com/cloudwatch/home?region=${var.region}#dashboards/dashboard/${aws_cloudwatch_dashboard.services.dashboard_name}"
}
