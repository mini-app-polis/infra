output "doppler_sync_role_arn" {
  description = "Paste into each Doppler config's AWS Parameter Store integration."
  value       = aws_iam_role.doppler_sync.arn
}

output "cogs" {
  description = "Per cog: the repository variables its deploy job reads, and where to look when a job dead-letters."
  value = {
    for name, m in {
      evaluator     = module.evaluator
      deejay        = module.deejay
      transcription = module.transcription
    } :
    name => {
      AWS_DEPLOY_ROLE_ARN = m.deploy_role_arn
      AWS_FUNCTION_NAME   = m.function_name
      AWS_REGION          = var.region
      queue_url           = m.queue_url
      dlq_url             = m.dlq_url
      alerts_topic_arn    = m.alerts_topic_arn
    }
  }
}

output "producer_user_name" {
  description = "Mint its access key by hand, straight into Doppler."
  value       = aws_iam_user.producer.name
}
