# One-time adoption of what the three cog repositories' local states managed.
#
# Generated from those states' resource ids. Apply once; the plan must show
# only imports and tag updates (Repo moves to mini-app-polis/infra, Component
# is set per cog) — no replacements, no destroys. Then delete this file.


# ── evaluator ──

import {
  to = aws_budgets_budget.monthly
  id = "400200465748:evaluator-monthly"
}

import {
  to = module.evaluator.aws_cloudwatch_log_group.worker
  id = "/aws/lambda/evaluator-worker"
}

import {
  to = module.evaluator.aws_cloudwatch_metric_alarm.dlq_not_empty
  id = "evaluator-dlq-not-empty"
}

import {
  to = aws_iam_openid_connect_provider.github
  id = "arn:aws:iam::400200465748:oidc-provider/token.actions.githubusercontent.com"
}

import {
  to = module.evaluator.aws_iam_role.deploy
  id = "evaluator-ci-deploy"
}

import {
  to = module.evaluator.aws_iam_role.worker
  id = "evaluator-worker"
}

import {
  to = module.evaluator.aws_iam_role_policy.deploy
  id = "evaluator-ci-deploy:evaluator-ci-deploy"
}

import {
  to = module.evaluator.aws_iam_role_policy.worker
  id = "evaluator-worker:evaluator-worker"
}

import {
  to = aws_iam_user.producer
  id = "evaluator-producer"
}

import {
  to = aws_iam_user_policy.producer
  id = "evaluator-producer:evaluator-producer-send"
}

import {
  to = module.evaluator.aws_lambda_event_source_mapping.jobs
  id = "2a2b165f-301d-44a2-85e0-bb74cb01c72d"
}

import {
  to = module.evaluator.aws_lambda_function.worker
  id = "evaluator-worker"
}

import {
  to = module.evaluator.aws_sns_topic.alerts
  id = "arn:aws:sns:us-east-1:400200465748:evaluator-alerts"
}

import {
  to = module.evaluator.aws_sns_topic_subscription.alerts_email
  id = "arn:aws:sns:us-east-1:400200465748:evaluator-alerts:a55c030d-b7c8-41d0-bda2-07a3f53572e9"
}

import {
  to = module.evaluator.aws_sqs_queue.dlq
  id = "https://sqs.us-east-1.amazonaws.com/400200465748/evaluator-jobs-dlq"
}

import {
  to = module.evaluator.aws_sqs_queue.jobs
  id = "https://sqs.us-east-1.amazonaws.com/400200465748/evaluator-jobs"
}

import {
  to = module.evaluator.aws_sqs_queue_redrive_allow_policy.dlq
  id = "https://sqs.us-east-1.amazonaws.com/400200465748/evaluator-jobs-dlq"
}


# ── deejay ──

import {
  to = module.deejay.aws_cloudwatch_log_group.worker
  id = "/aws/lambda/deejay-worker"
}

import {
  to = module.deejay.aws_cloudwatch_metric_alarm.dlq_not_empty
  id = "deejay-dlq-not-empty"
}

import {
  to = module.deejay.aws_iam_role.deploy
  id = "deejay-ci-deploy"
}

import {
  to = module.deejay.aws_iam_role.worker
  id = "deejay-worker"
}

import {
  to = module.deejay.aws_iam_role_policy.deploy
  id = "deejay-ci-deploy:deejay-ci-deploy"
}

import {
  to = module.deejay.aws_iam_role_policy.worker
  id = "deejay-worker:deejay-worker"
}

import {
  to = module.deejay.aws_lambda_event_source_mapping.jobs
  id = "1d964b65-bed6-445d-acfc-d729545c6b05"
}

import {
  to = module.deejay.aws_lambda_function.worker
  id = "deejay-worker"
}

import {
  to = module.deejay.aws_sns_topic.alerts
  id = "arn:aws:sns:us-east-1:400200465748:deejay-alerts"
}

import {
  to = module.deejay.aws_sns_topic_subscription.alerts_email
  id = "arn:aws:sns:us-east-1:400200465748:deejay-alerts:67c1c24d-f7a0-4b3e-a46a-77a4177172ed"
}

import {
  to = module.deejay.aws_sqs_queue.dlq
  id = "https://sqs.us-east-1.amazonaws.com/400200465748/deejay-jobs-dlq"
}

import {
  to = module.deejay.aws_sqs_queue.jobs
  id = "https://sqs.us-east-1.amazonaws.com/400200465748/deejay-jobs"
}

import {
  to = module.deejay.aws_sqs_queue_redrive_allow_policy.dlq
  id = "https://sqs.us-east-1.amazonaws.com/400200465748/deejay-jobs-dlq"
}


# ── transcription ──

import {
  to = module.transcription.aws_cloudwatch_log_group.worker
  id = "/aws/lambda/transcription-worker"
}

import {
  to = module.transcription.aws_cloudwatch_metric_alarm.dlq_not_empty
  id = "transcription-dlq-not-empty"
}

import {
  to = module.transcription.aws_iam_role.deploy
  id = "transcription-ci-deploy"
}

import {
  to = module.transcription.aws_iam_role.worker
  id = "transcription-worker"
}

import {
  to = module.transcription.aws_iam_role_policy.deploy
  id = "transcription-ci-deploy:transcription-ci-deploy"
}

import {
  to = module.transcription.aws_iam_role_policy.worker
  id = "transcription-worker:transcription-worker"
}

import {
  to = module.transcription.aws_lambda_event_source_mapping.jobs
  id = "e469216b-e890-4fa2-9b2f-a0899cf01ceb"
}

import {
  to = module.transcription.aws_lambda_function.worker
  id = "transcription-worker"
}

import {
  to = module.transcription.aws_sns_topic.alerts
  id = "arn:aws:sns:us-east-1:400200465748:transcription-alerts"
}

import {
  to = module.transcription.aws_sns_topic_subscription.alerts_email
  id = "arn:aws:sns:us-east-1:400200465748:transcription-alerts:dbb1c481-7a44-471b-aef1-de0b6186f626"
}

import {
  to = module.transcription.aws_sqs_queue.dlq
  id = "https://sqs.us-east-1.amazonaws.com/400200465748/transcription-jobs-dlq"
}

import {
  to = module.transcription.aws_sqs_queue.jobs
  id = "https://sqs.us-east-1.amazonaws.com/400200465748/transcription-jobs"
}

import {
  to = module.transcription.aws_sqs_queue_redrive_allow_policy.dlq
  id = "https://sqs.us-east-1.amazonaws.com/400200465748/transcription-jobs-dlq"
}
