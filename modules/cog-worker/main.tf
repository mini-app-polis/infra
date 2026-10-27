# One pipeline cog's runtime: its queue and dead-letter queue, the worker
# function and the mapping that feeds it, the role CI deploys code through,
# and alarms that tell someone when a job is dead-lettered, the queue has
# stopped draining, or a job is running close to the function timeout.
#
# The cog's repository owns the function's code and deploys it with
# UpdateFunctionCode, nothing more. Everything else is here.

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  tags = { Component = "${var.name}-worker" }

  # SQS requires a FIFO queue's name to end .fifo; the producer derives the
  # same names (api-kaianolevine-com job_queue.queue_name).
  queue_suffix = var.fifo ? ".fifo" : ""

  # The worker's own Doppler project is named for its repository. Its prd
  # config holds each parameter under the name the code reads, as a
  # reference to the vault value the module block names, and syncs to a
  # prefix of its own (README.md, "Doppler layout").
  doppler_project = element(split("/", var.github_repo), 1)

  ssm_prefix = "/mini-app-polis/${local.doppler_project}/prd/"

  ssm_parameters          = { for name in keys(var.ssm_parameters) : name => name }
  ssm_optional_parameters = { for name in keys(var.ssm_optional_parameters) : name => name }

  ssm_parameter_arns = [
    for p in distinct(values(merge(local.ssm_parameters, local.ssm_optional_parameters))) :
    "arn:aws:ssm:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:parameter${local.ssm_prefix}${p}"
  ]
}

# ── Queue ────────────────────────────────────────────────────────────────

resource "aws_sqs_queue" "dlq" {
  name       = "${var.name}-jobs-dlq${local.queue_suffix}"
  fifo_queue = var.fifo # a FIFO queue's dead-letter queue must be FIFO too

  # The maximum. A message lands here because something needs a person, and
  # a person is slower than the work queue's four days.
  message_retention_seconds = 1209600 # 14 days

  tags = local.tags
}

resource "aws_sqs_queue" "jobs" {
  name       = "${var.name}-jobs${local.queue_suffix}"
  fifo_queue = var.fifo

  # The producer sends no deduplication id: an identical body within five
  # minutes is one job, which the API's dispatch claims already make true.
  content_based_deduplication = var.fifo ? true : null

  # Must exceed the function timeout, or SQS redelivers a job that is still
  # running and it runs twice. Derived so the two cannot drift apart.
  visibility_timeout_seconds = var.timeout_seconds + 60

  receive_wait_time_seconds = 20     # long polling
  message_retention_seconds = 345600 # 4 days

  # Not automatic: without it a poison message retries forever.
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = var.max_receive_count
  })

  tags = local.tags
}

# ── Scheduled jobs ───────────────────────────────────────────────────────
# A schedule is a producer like the API: it puts a message on the queue, and
# the worker takes it in turn. Only a cog with schedules gets these.

resource "aws_cloudwatch_event_rule" "schedule" {
  for_each = var.schedules

  name                = "${var.name}-${each.key}"
  description         = "Puts a ${each.key} job on ${aws_sqs_queue.jobs.name}."
  schedule_expression = each.value.expression

  tags = local.tags
}

resource "aws_cloudwatch_event_target" "schedule" {
  for_each = var.schedules

  rule  = aws_cloudwatch_event_rule.schedule[each.key].name
  arn   = aws_sqs_queue.jobs.arn
  input = each.value.body

  # The API's message group for this queue (job_queue.message_group): one
  # group keeps a FIFO queue strictly serial.
  dynamic "sqs_target" {
    for_each = var.fifo ? [var.name] : []
    content {
      message_group_id = sqs_target.value
    }
  }
}

# EventBridge sends as itself, so the queue must allow it, and only from
# this cog's own rules.
resource "aws_sqs_queue_policy" "schedule" {
  count = length(var.schedules) > 0 ? 1 : 0

  queue_url = aws_sqs_queue.jobs.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "ScheduledJobs"
      Effect    = "Allow"
      Principal = { Service = "events.amazonaws.com" }
      Action    = "sqs:SendMessage"
      Resource  = aws_sqs_queue.jobs.arn
      Condition = {
        ArnEquals = {
          "aws:SourceArn" = [for rule in aws_cloudwatch_event_rule.schedule : rule.arn]
        }
      }
    }]
  })
}

# Lets the console's DLQ redrive move a message back once its cause is fixed.
resource "aws_sqs_queue_redrive_allow_policy" "dlq" {
  queue_url = aws_sqs_queue.dlq.id

  redrive_allow_policy = jsonencode({
    redrivePermission = "byQueue"
    sourceQueueArns   = [aws_sqs_queue.jobs.arn]
  })
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
  # The event source mapping receives with this role's permissions.
  statement {
    actions = [
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes",
      "sqs:ChangeMessageVisibility",
    ]
    resources = [aws_sqs_queue.jobs.arn]
  }

  statement {
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.worker.arn}:*"]
  }

  # Its own secrets, by name. GetParameters and nothing wider — not
  # GetParametersByPath, which would reach every secret Doppler syncs. No
  # KMS grant: SecureStrings under the AWS-managed aws/ssm key are
  # decryptable by any principal in the account allowed to read them.
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

# Declared rather than left to Lambda, which creates one that retains forever.
resource "aws_cloudwatch_log_group" "worker" {
  name              = "/aws/lambda/${var.name}-worker"
  retention_in_days = var.log_retention_days
  tags              = local.tags
}

# Bootstrap payload, read once at create and never again (ignore_changes
# below). The function cannot exist without code, and CI cannot deploy
# until it exists. Deliberately not runnable: the handler names a package
# this archive lacks, so a message arriving before the first deploy fails
# and is dead-lettered rather than consumed and discarded.
data "archive_file" "bootstrap" {
  type        = "zip"
  output_path = "${path.root}/.terraform/bootstrap-${var.name}.zip"

  source {
    filename = "PLACEHOLDER"
    content  = "Replaced by the first CI deploy. See modules/cog-worker/main.tf.\n"
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

  timeout                        = var.timeout_seconds
  memory_size                    = var.memory_mb
  reserved_concurrent_executions = var.reserved_concurrency

  # Configuration only. The SSM_* entries name the parameters the worker
  # loads itself at cold start; no secret value is here, in state or in a
  # plan.
  environment {
    variables = merge(
      {
        ENVIRONMENT         = "production"
        KAIANO_API_BASE_URL = var.api_base_url
      },
      var.environment,
      {
        SSM_PREFIX              = local.ssm_prefix
        SSM_PARAMETERS          = jsonencode(local.ssm_parameters)
        SSM_OPTIONAL_PARAMETERS = jsonencode(local.ssm_optional_parameters)
      },
    )
  }

  depends_on = [aws_cloudwatch_log_group.worker]

  lifecycle {
    # Terraform owns the configuration; CI owns the code. Without this every
    # apply after a deploy would roll the function back to the placeholder.
    ignore_changes = [filename, source_code_hash]
  }

  tags = local.tags
}

resource "aws_lambda_event_source_mapping" "jobs" {
  event_source_arn = aws_sqs_queue.jobs.arn
  function_name    = aws_lambda_function.worker.arn
  enabled          = true

  # One job per invocation: the visibility-timeout arithmetic is per job.
  batch_size              = 1
  function_response_types = ["ReportBatchItemFailures"]

  # Absent when the reservation is the ceiling: the mapping's maximum cannot
  # go below 2, and AWS refuses one above the function's reservation.
  dynamic "scaling_config" {
    for_each = var.max_concurrency == null ? [] : [var.max_concurrency]
    content {
      maximum_concurrency = scaling_config.value
    }
  }

  tags = local.tags
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

    # Without this, any repository on GitHub could assume the role. Pinned
    # to main, where the cog's release job and its deploy run: a pull
    # request, another branch or another workflow in the cog's repository
    # cannot push code to the production function. A by-hand redeploy is
    # dispatched from main too.
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["${coalesce(var.github_oidc_subject, "repo:${var.github_repo}")}:ref:refs/heads/main"]
    }
  }
}

resource "aws_iam_role" "deploy" {
  name               = "${var.name}-ci-deploy"
  assume_role_policy = data.aws_iam_policy_document.deploy_assume.json
  tags               = local.tags
}

data "aws_iam_policy_document" "deploy" {
  # Code, and the reads a deploy needs to confirm itself. Not
  # UpdateFunctionConfiguration: repointing the worker takes a reviewed
  # change here. GetFunctionConfiguration is separate from GetFunction and
  # `aws lambda wait function-updated` needs it.
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

resource "aws_cloudwatch_metric_alarm" "dlq_not_empty" {
  alarm_name          = "${var.name}-dlq-not-empty"
  alarm_description   = "A job failed every retry and is sitting in the dead-letter queue."
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  statistic           = "Maximum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    QueueName = aws_sqs_queue.dlq.name
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = local.tags
}

# The consumer has stopped, not the job. A message that keeps failing is
# gone to the dead-letter queue by max_in_flight_seconds; one still in the
# work queue past that was never picked up — the event source mapping is
# disabled, the function is throttled to zero, or deploys are broken. The
# dead-letter alarm cannot see this: nothing ever reaches it. Derived from
# the same values as the redrive, so the two cannot drift apart.
resource "aws_cloudwatch_metric_alarm" "queue_stalled" {
  alarm_name          = "${var.name}-queue-stalled"
  alarm_description   = "A job has waited longer than every retry could take, so nothing is consuming ${aws_sqs_queue.jobs.name}."
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateAgeOfOldestMessage"
  statistic           = "Maximum"
  period              = 300
  evaluation_periods  = 1
  threshold           = var.max_receive_count * aws_sqs_queue.jobs.visibility_timeout_seconds
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    QueueName = aws_sqs_queue.jobs.name
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = local.tags
}

# The job is slow, not failed. A job that reaches the timeout is killed
# mid-run and retried (PIPE-020 makes it say so, but cannot tell a hung job
# from a slow healthy one); this fires while the longest job still fits, so
# the timeout can be raised before healthy jobs start dying at it. A job
# killed at the timeout also lands here, its duration being the timeout.
# Derived from timeout_seconds, so the two cannot drift apart.
resource "aws_cloudwatch_metric_alarm" "duration_near_timeout" {
  alarm_name          = "${var.name}-duration-near-timeout"
  alarm_description   = "A job ran past ${var.duration_alarm_ratio * 100}% of the ${var.timeout_seconds}-second function timeout, so a slower one would be killed mid-run."
  namespace           = "AWS/Lambda"
  metric_name         = "Duration"
  statistic           = "Maximum"
  period              = 300
  evaluation_periods  = 1
  threshold           = var.timeout_seconds * 1000 * var.duration_alarm_ratio
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.worker.function_name
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = local.tags
}
