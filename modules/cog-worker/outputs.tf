output "queue_url" {
  value = aws_sqs_queue.jobs.url
}

output "queue_arn" {
  value = aws_sqs_queue.jobs.arn
}

output "queue_name" {
  description = "The QueueName dimension its SQS metrics are published under."
  value       = aws_sqs_queue.jobs.name
}

output "dlq_name" {
  value = aws_sqs_queue.dlq.name
}

output "dlq_url" {
  description = "For watching a poison message arrive, and redriving it once fixed."
  value       = aws_sqs_queue.dlq.url
}

output "function_name" {
  description = "The cog repository's AWS_FUNCTION_NAME variable."
  value       = aws_lambda_function.worker.function_name
}

output "worker_role_name" {
  description = "The function's execution role, for a grant the module does not make (a cog's reads outside ssm_prefix)."
  value       = aws_iam_role.worker.name
}

output "deploy_role_arn" {
  description = "The cog repository's AWS_DEPLOY_ROLE_ARN variable."
  value       = aws_iam_role.deploy.arn
}

output "alerts_topic_arn" {
  description = "Check the email subscription is Confirmed, not PendingConfirmation."
  value       = aws_sns_topic.alerts.arn
}

output "max_in_flight_seconds" {
  description = <<-DESC
    The longest a job can spend between enqueue and the dead-letter queue:
    every delivery holds it for one visibility timeout. api-kaianolevine-com's
    dispatch claim window must be longer, or a file still being retried is
    dispatched again; the root checks it.
  DESC
  value       = var.max_receive_count * aws_sqs_queue.jobs.visibility_timeout_seconds
}

output "doppler_project" {
  description = "The worker's own Doppler project, named for its repository."
  value       = local.doppler_project
}

output "doppler_references" {
  description = "Each name the code reads → the vault's name for its value: what the worker's own Doppler config references."
  value       = merge(var.ssm_parameters, var.ssm_optional_parameters)
}

output "settings_allowlist" {
  description = "The worker's SETTINGS_ALLOWLIST: the comma-separated, sorted names it loads whose value is in mini-app-polis-settings. Names only."
  value       = local.settings_allowlist
}
