output "queue_url" {
  value = aws_sqs_queue.jobs.url
}

output "queue_arn" {
  value = aws_sqs_queue.jobs.arn
}

output "dlq_url" {
  description = "For watching a poison message arrive, and redriving it once fixed."
  value       = aws_sqs_queue.dlq.url
}

output "function_name" {
  description = "The cog repository's AWS_FUNCTION_NAME variable."
  value       = aws_lambda_function.worker.function_name
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
