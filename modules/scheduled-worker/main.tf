# A function on a schedule: no queue, no event source mapping. For a cog
# whose work is to look at something every so often — watcher-cog, which
# lists its Drive folders once a minute and asks the API for what it finds.
#
# The sibling of modules/cog-worker, not a mode of it: giving that module's
# queue a count would move the address of every live cog's queue. The
# function, its role, its log group and the deploy role are the same shape
# there and here, and should stay so.
#
# The cog's repository owns the function's code and deploys it with
# UpdateFunctionCode, nothing more. Everything else is here.

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  tags = { Component = "${var.name}-worker" }

  ssm_parameter_arns = [
    for p in distinct(values(merge(var.ssm_parameters, var.ssm_optional_parameters))) :
    "arn:aws:ssm:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:parameter${var.ssm_prefix}${p}"
  ]
}

# ── Worker ───────────────────────────────────────────────────────────────

data "aws_iam_policy_document" "worker_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "worker" {
  name               = "${var.name}-worker"
  assume_role_policy = data.aws_iam_policy_document.worker_assume.json
  tags               = local.tags
}

data "aws_iam_policy_document" "worker" {
  statement {
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.worker.arn}:*"]
  }

  # Its own secrets, by name. GetParameters and nothing wider; see
  # modules/cog-worker for why.
  dynamic "statement" {
    for_each = length(local.ssm_parameter_arns) > 0 ? [1] : []
    content {
      actions   = ["ssm:GetParameters"]
      resources = local.ssm_parameter_arns
    }
  }
}

resource "aws_iam_role_policy" "worker" {
  name   = "${var.name}-worker"
  role   = aws_iam_role.worker.id
  policy = data.aws_iam_policy_document.worker.json
}

# Declared rather than left to Lambda, which creates one that retains
# forever. A once-a-minute function writes a lot of nothing; keep its
# empty ticks to a line and its retention short.
resource "aws_cloudwatch_log_group" "worker" {
  name              = "/aws/lambda/${var.name}-worker"
  retention_in_days = var.log_retention_days
  tags              = local.tags
}

# Bootstrap payload; see modules/cog-worker. Not runnable, so a tick that
# fires before the first deploy fails loudly instead of doing nothing.
data "archive_file" "bootstrap" {
  type        = "zip"
  output_path = "${path.root}/.terraform/bootstrap-${var.name}.zip"

  source {
    filename = "PLACEHOLDER"
    content  = "Replaced by the first CI deploy. See modules/scheduled-worker/main.tf.\n"
  }
}

resource "aws_lambda_function" "worker" {
  function_name = "${var.name}-worker"
  role          = aws_iam_role.worker.arn
  runtime       = var.runtime
  handler       = var.handler
  architectures = [var.architecture]

  filename         = data.archive_file.bootstrap.output_path
  source_code_hash = data.archive_file.bootstrap.output_base64sha256

  timeout     = var.timeout_seconds
  memory_size = var.memory_mb

  # One tick at a time. Two overlapping ticks are harmless — the API's
  # claims make the second a no-op — but they are never useful.
  reserved_concurrent_executions = 1

  environment {
    variables = merge(
      {
        ENVIRONMENT         = "production"
        KAIANO_API_BASE_URL = var.api_base_url
      },
      var.environment,
      {
        SSM_PREFIX              = var.ssm_prefix
        SSM_PARAMETERS          = jsonencode(var.ssm_parameters)
        SSM_OPTIONAL_PARAMETERS = jsonencode(var.ssm_optional_parameters)
      },
    )
  }

  depends_on = [aws_cloudwatch_log_group.worker]

  lifecycle {
    # Terraform owns the configuration; CI owns the code.
    ignore_changes = [filename, source_code_hash]

    precondition {
      condition     = var.timeout_seconds < var.schedule_interval_seconds
      error_message = "timeout_seconds must be shorter than the schedule interval, or a slow tick runs into the next one."
    }
  }

  tags = local.tags
}

# A scheduled invocation is asynchronous, and Lambda retries a failed or
# throttled async event for up to six hours by default. Here the next tick
# is the retry: a stale tick replayed later only duplicates it, and a
# backlog of them behind a reservation of one would crowd out the current
# one. So: no retries, and an event older than one interval is dropped.
resource "aws_lambda_function_event_invoke_config" "worker" {
  function_name                = aws_lambda_function.worker.function_name
  maximum_retry_attempts       = 0
  maximum_event_age_in_seconds = max(60, var.schedule_interval_seconds)
}

# ── Schedule ─────────────────────────────────────────────────────────────

resource "aws_cloudwatch_event_rule" "schedule" {
  name                = "${var.name}-schedule"
  description         = "Invokes ${var.name}-worker every ${var.schedule_interval_seconds}s."
  schedule_expression = var.schedule_interval_seconds == 60 ? "rate(1 minute)" : "rate(${var.schedule_interval_seconds / 60} minutes)"

  # The cutover switch. Off, the function exists and can be deployed and
  # invoked by hand while whatever it replaces is still running.
  state = var.enabled ? "ENABLED" : "DISABLED"

  tags = local.tags
}

resource "aws_cloudwatch_event_target" "schedule" {
  rule = aws_cloudwatch_event_rule.schedule.name
  arn  = aws_lambda_function.worker.arn
}

resource "aws_lambda_permission" "schedule" {
  statement_id  = "AllowEventBridgeSchedule"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.worker.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.schedule.arn
}

# ── Deploy ───────────────────────────────────────────────────────────────

data "aws_iam_policy_document" "deploy_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.github_oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Without this, any repository on GitHub could assume the role.
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repo}:*"]
    }
  }
}

resource "aws_iam_role" "deploy" {
  name               = "${var.name}-ci-deploy"
  assume_role_policy = data.aws_iam_policy_document.deploy_assume.json
  tags               = local.tags
}

data "aws_iam_policy_document" "deploy" {
  statement {
    actions = [
      "lambda:UpdateFunctionCode",
      "lambda:GetFunction",
      "lambda:GetFunctionConfiguration",
    ]
    resources = [aws_lambda_function.worker.arn]
  }
}

resource "aws_iam_role_policy" "deploy" {
  name   = "${var.name}-ci-deploy"
  role   = aws_iam_role.deploy.id
  policy = data.aws_iam_policy_document.deploy.json
}

# ── Alerting ─────────────────────────────────────────────────────────────

resource "aws_sns_topic" "alerts" {
  name = "${var.name}-alerts"
  tags = local.tags
}

# Stays PendingConfirmation — delivering nothing — until the emailed link is
# clicked. Applying cleanly is not the same as being wired up.
resource "aws_sns_topic_subscription" "alerts_email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# The once-per-outage signal. A failed tick is an error invocation; the
# function has no memory to report the first one and stay quiet after, so
# the alarm does it: it notifies on the change into ALARM and back to OK,
# not on every failed tick. Several failing ticks in a window, so one
# transient Drive or API error does not page. A schedule that stops firing
# produces no data here at all — Healthchecks, which fires on absence, is
# what catches that.
resource "aws_cloudwatch_metric_alarm" "errors" {
  alarm_name          = "${var.name}-failing"
  alarm_description   = "${var.name}-worker ticks are failing. Its log group and Sentry say which folder and why."
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  statistic           = "Sum"
  period              = var.schedule_interval_seconds
  evaluation_periods  = var.error_alarm_window
  datapoints_to_alarm = var.error_alarm_threshold
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.worker.function_name
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = local.tags
}
