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
