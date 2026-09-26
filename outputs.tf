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

output "watcher" {
  description = "watcher-cog's repository variables, and whether its schedule is on."
  value = {
    AWS_DEPLOY_ROLE_ARN = module.watcher.deploy_role_arn
    AWS_FUNCTION_NAME   = module.watcher.function_name
    AWS_REGION          = var.region
    alerts_topic_arn    = module.watcher.alerts_topic_arn
    schedule_state      = module.watcher.schedule_state
  }
}

locals {
  # api-kaianolevine-com's CLAIM_WINDOW (services/dispatch_claims.py). The
  # watcher asks for every file on every tick, and the API dispatches a
  # file again once its claim is this old — on the reasoning that its job
  # has by then failed through every retry. That holds only while no job
  # can still be in flight after this long.
  dispatch_claim_window_seconds = 6 * 3600

  cog_max_in_flight_seconds = {
    evaluator     = module.evaluator.max_in_flight_seconds
    deejay        = module.deejay.max_in_flight_seconds
    transcription = module.transcription.max_in_flight_seconds
  }
}

output "dispatch_claim_headroom_seconds" {
  description = "Per cog: how far the API's dispatch claim window outlasts its longest possible job."
  value = {
    for name, seconds in local.cog_max_in_flight_seconds :
    name => local.dispatch_claim_window_seconds - seconds
  }

  precondition {
    condition = alltrue([
      for seconds in values(local.cog_max_in_flight_seconds) :
      seconds < local.dispatch_claim_window_seconds
    ])
    error_message = "A cog's queue can hold a job in flight longer than the API's six-hour dispatch claim window, so the watcher would dispatch a file that is still being retried. Shorten that cog's timeout or max_receive_count, or lengthen CLAIM_WINDOW in api-kaianolevine-com and dispatch_claim_window_seconds here together."
  }
}

output "producer_user_name" {
  description = "Mint its access key by hand, straight into Doppler."
  value       = aws_iam_user.producer.name
}

output "ci_roles" {
  description = "Repository variables for this repo's workflow: AWS_PLAN_ROLE_ARN and AWS_APPLY_ROLE_ARN."
  value = {
    AWS_PLAN_ROLE_ARN  = aws_iam_role.infra_plan.arn
    AWS_APPLY_ROLE_ARN = aws_iam_role.infra_apply.arn
  }
}
