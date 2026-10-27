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

output "schedule_state" {
  description = "ENABLED or DISABLED — whether the cutover has happened."
  value       = aws_cloudwatch_event_rule.schedule.state
}

output "doppler_project" {
  description = "The worker's own Doppler project, named for its repository."
  value       = local.doppler_project
}

output "doppler_references" {
  description = "Each name the code reads → the vault's name for its value: what the worker's own Doppler config references."
  value       = merge(var.ssm_parameters, var.ssm_optional_parameters)
}
