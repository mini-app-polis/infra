# The fleet on one screen: each API's requests, then every cog's function
# and queues. The cog rows are metrics AWS publishes on its own, at no
# cost. The API rows are custom metrics published by common-python-utils'
# request_metrics middleware (MiniAppPolis/Api) and billed per metric.
# Dashboards are free up to three per account at 50 metrics each; this one
# references about 42.
#
# Built from the cog modules, so a cog added to cogs.tf and to the maps
# below gets its row; an API gets its row by being added to
# dashboard_apis. Postgres has its own, mini-app-polis-data, at the end of
# this file.

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
  dashboard_apis = ["api-kaianolevine-com", "api-deejaytools"]

  # Per API, the routes it gives their own Latency series (the `routes`
  # argument to RequestMetricsMiddleware). Must match what the API
  # publishes: a route listed here and not there draws an empty line.
  dashboard_api_routes = {
    "api-kaianolevine-com" = ["/v1/standards/catalog", "/v1/evaluations"]
    "api-deejaytools" = [
      "/v1/checkins",
      "/v1/queue/promote",
      "/v1/queue/{session_id}/active",
      "/v1/queue/{session_id}/waiting",
    ]
  }

  dashboard_row_height = 6
  dashboard_header     = 2

  api_rows = [
    for i, service in local.dashboard_apis : concat([
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
      # Only for an API that publishes per-route series: CloudWatch rejects
      # a widget with no metrics.
      ], length(lookup(local.dashboard_api_routes, service, [])) == 0 ? [] : [
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
    ])
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
      {
        # A scheduled tick that never ran: throttled or delayed past the
        # function's maximum event age. Invisible to the errors alarm and to
        # Healthchecks, which any other target's tick still pings.
        type   = "metric"
        x      = 12
        y      = local.scheduled_rows_top + i * local.dashboard_row_height
        width  = 6
        height = local.dashboard_row_height
        properties = {
          title  = "${name}: dropped ticks"
          region = var.region
          view   = "timeSeries"
          period = 3600
          metrics = [
            ["AWS/Lambda", "AsyncEventsDropped", "FunctionName", local.dashboard_scheduled_cogs[name].function_name, { stat = "Sum", label = "dropped", color = "#d62728" }],
            [".", "AsyncEventAge", ".", ".", { stat = "Maximum", label = "oldest wait (ms)", yAxis = "right" }],
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

# ── Data ─────────────────────────────────────────────────────────────────

# The two production Postgres databases, one row each, from what db-poller
# publishes every five minutes (database_metrics.tf, where the alarms are).
# Its own dashboard so the services one stays under the free 50 metrics;
# this one references nine per database. A gap in a row is the database —
# or the poller — not reporting, which is what the unreachable alarm fires
# on.

locals {
  data_widget_width = 4

  data_rows = [
    for i, db in local.postgres_databases : [
      {
        type   = "metric"
        x      = 0
        y      = local.dashboard_header + i * local.dashboard_row_height
        width  = local.data_widget_width
        height = local.dashboard_row_height
        properties = {
          title  = "${db}: connections"
          region = var.region
          view   = "timeSeries"
          stat   = "Maximum"
          period = 300
          metrics = [
            ["MiniAppPolis/Postgres", "Connections", "Database", db, { label = "connections" }],
            [".", "ConnectionUtilization", ".", ".", { label = "% of max", yAxis = "right" }],
          ]
          yAxis = { right = { min = 0, max = 100 } }
          annotations = {
            # The connections alarm's threshold.
            horizontal = [{ label = "alarm", value = 80, yAxis = "right" }]
          }
        }
      },
      {
        type   = "metric"
        x      = local.data_widget_width
        y      = local.dashboard_header + i * local.dashboard_row_height
        width  = local.data_widget_width
        height = local.dashboard_row_height
        properties = {
          title  = "${db}: size (bytes)"
          region = var.region
          view   = "timeSeries"
          stat   = "Maximum"
          period = 300
          metrics = [
            ["MiniAppPolis/Postgres", "DatabaseSize", "Database", db, { label = "database" }],
          ]
        }
      },
      {
        type   = "metric"
        x      = 2 * local.data_widget_width
        y      = local.dashboard_header + i * local.dashboard_row_height
        width  = local.data_widget_width
        height = local.dashboard_row_height
        properties = {
          title  = "${db}: cache hit ratio (%)"
          region = var.region
          view   = "timeSeries"
          stat   = "Minimum"
          period = 300
          metrics = [
            ["MiniAppPolis/Postgres", "CacheHitRatio", "Database", db, { label = "hit %" }],
          ]
          yAxis = { left = { max = 100 } }
        }
      },
      {
        type   = "metric"
        x      = 3 * local.data_widget_width
        y      = local.dashboard_header + i * local.dashboard_row_height
        width  = local.data_widget_width
        height = local.dashboard_row_height
        properties = {
          title  = "${db}: oldest transaction (s)"
          region = var.region
          view   = "timeSeries"
          stat   = "Maximum"
          period = 300
          metrics = [
            ["MiniAppPolis/Postgres", "OldestTransactionAge", "Database", db, { label = "oldest open" }],
          ]
        }
      },
      {
        # Both series are running totals from pg_stat_statements, so the
        # mean over each period is the change in time over the change in
        # calls. The IF leaves a gap, not a zero, for a period with no
        # queries — and for the period after a stats reset, where both
        # changes go negative.
        type   = "metric"
        x      = 4 * local.data_widget_width
        y      = local.dashboard_header + i * local.dashboard_row_height
        width  = local.data_widget_width
        height = local.dashboard_row_height
        properties = {
          title  = "${db}: mean query time (ms)"
          region = var.region
          view   = "timeSeries"
          period = 300
          metrics = [
            [{ expression = "IF(DIFF(calls) > 0, DIFF(exec) / DIFF(calls))", label = "mean", id = "mean" }],
            ["MiniAppPolis/Postgres", "StatementExecTime", "Database", db, { stat = "Maximum", id = "exec", visible = false }],
            [".", "StatementCalls", ".", ".", { stat = "Maximum", id = "calls", visible = false }],
          ]
        }
      },
      {
        type   = "metric"
        x      = 5 * local.data_widget_width
        y      = local.dashboard_header + i * local.dashboard_row_height
        width  = local.data_widget_width
        height = local.dashboard_row_height
        properties = {
          title  = "${db}: WAL archive"
          region = var.region
          view   = "timeSeries"
          period = 300
          metrics = [
            ["MiniAppPolis/Postgres", "WalDirSize", "Database", db, { stat = "Maximum", label = "WAL dir (bytes)" }],
            [{ expression = "DIFF(failed)", label = "archive failures", id = "failures", yAxis = "right", color = "#d62728" }],
            ["MiniAppPolis/Postgres", "ArchiveFailedCount", "Database", db, { stat = "Maximum", id = "failed", visible = false }],
          ]
          annotations = {
            # The WAL-dir-filling alarm's threshold.
            horizontal = [{ label = "alarm", value = local.postgres_wal_dir_alarm_bytes }]
          }
        }
      },
    ]
  ]
}

resource "aws_cloudwatch_dashboard" "data" {
  dashboard_name = "mini-app-polis-data"

  dashboard_body = jsonencode({
    widgets = concat(
      [{
        type   = "text"
        x      = 0
        y      = 0
        width  = 24
        height = local.dashboard_header
        properties = {
          markdown = "## mini-app-polis data\nOne row per production Postgres database, published every five minutes by db-poller (mini-app-polis/db-ops). A gap means the database or the poller is not reporting. Alarms email through mini-app-polis-data-alerts. Defined in mini-app-polis/infra `observability.tf` and `database_metrics.tf`."
        }
      }],
      flatten(local.data_rows),
    )
  })
}

output "data_dashboard_url" {
  description = "The databases' dashboard in the CloudWatch console."
  value       = "https://${var.region}.console.aws.amazon.com/cloudwatch/home?region=${var.region}#dashboards/dashboard/${aws_cloudwatch_dashboard.data.dashboard_name}"
}
