# One module per pipeline cog. Adding a cog is adding a block here; its
# repository then needs AWS_DEPLOY_ROLE_ARN, AWS_REGION and
# AWS_FUNCTION_NAME (terraform output cogs) and a confirmed alert email.
#
# handler, architecture and the runtime must match the cog's deploy job in
# its ci.yml. Secrets are listed by name only; their values are in Doppler.

module "evaluator" {
  source = "./modules/cog-worker"

  name                     = "evaluator"
  github_repo              = "mini-app-polis/evaluator-cog"
  github_oidc_provider_arn = aws_iam_openid_connect_provider.github.arn
  alert_email              = local.alert_email
  api_base_url             = var.kaiano_api_base_url

  handler         = "evaluator_cog.adapters.lambda_worker.lambda_handler"
  architecture    = "arm64"
  timeout_seconds = 300
  memory_mb       = 1024

  # A fleet pass is N concurrent jobs, each posting back to one Railway
  # container; four leaves the API most of its headroom.
  max_concurrency = 4

  ssm_parameters = {
    EVALUATOR_COG_API_KEY = "EVALUATOR_COG_API_KEY"
    GITHUB_TOKEN          = "GITHUB_TOKEN"
  }
  ssm_optional_parameters = {
    ANTHROPIC_API_KEY = "ANTHROPIC_API_KEY"
    SENTRY_DSN        = "SENTRY_DSN"
  }
}

module "deejay" {
  source = "./modules/cog-worker"

  name                     = "deejay"
  github_repo              = "mini-app-polis/deejay-cog"
  github_oidc_provider_arn = aws_iam_openid_connect_provider.github.arn
  alert_email              = local.alert_email
  api_base_url             = var.kaiano_api_base_url

  # x86_64: cryptography, cffi and rpds-py ship compiled wheels the deploy
  # builds for x86_64-manylinux_2_17.
  handler         = "deejay_cog.worker.lambda_handler"
  architecture    = "x86_64"
  timeout_seconds = 900 # not yet measured; lower it once the slowest run is known
  memory_mb       = 1024

  # Serialised: two sweeps of one Drive folder race to upload and archive
  # the same files. 5 receives because a burst can throttle a good message.
  reserved_concurrency = 1
  max_receive_count    = 5

  environment = {
    SPOTIPY_REDIRECT_URI  = "http://127.0.0.1:8888/callback"
    VDJ_HISTORY_FOLDER_ID = "1HGxEr5ocY9JLtXcJqDRIOD95rXU6QLUW"
  }

  ssm_parameters = {
    DEEJAY_COG_API_KEY      = "DEEJAY_COG_API_KEY"
    GOOGLE_CREDENTIALS_JSON = "GOOGLE_CREDENTIALS_JSON"
  }
  ssm_optional_parameters = {
    SENTRY_DSN                = "SENTRY_DSN"
    SPOTIFY_RADIO_PLAYLIST_ID = "SPOTIFY_RADIO_PLAYLIST_ID"
    SPOTIPY_CLIENT_ID         = "SPOTIPY_CLIENT_ID"
    SPOTIPY_CLIENT_SECRET     = "SPOTIPY_CLIENT_SECRET"
    SPOTIPY_REFRESH_TOKEN     = "SPOTIPY_REFRESH_TOKEN"
  }
}

module "transcription" {
  source = "./modules/cog-worker"

  name                     = "transcription"
  github_repo              = "mini-app-polis/transcription-cog"
  github_oidc_provider_arn = aws_iam_openid_connect_provider.github.arn
  alert_email              = local.alert_email
  api_base_url             = var.kaiano_api_base_url

  handler         = "transcription_cog.worker.lambda_handler"
  architecture    = "arm64"
  timeout_seconds = 900
  memory_mb       = 512

  # One file per job, serialised.
  reserved_concurrency = 1
  max_receive_count    = 5

  ssm_parameters = {
    ANTHROPIC_API_KEY                  = "ANTHROPIC_API_KEY"
    ASANA_ACCESS_TOKEN                 = "ASANA_ACCESS_TOKEN"
    ASANA_INBOX_PROJECT_ID             = "ASANA_INBOX_PROJECT_ID"
    ASANA_WORKSPACE_ID                 = "ASANA_WORKSPACE_ID"
    GOOGLE_CREDENTIALS_JSON            = "GOOGLE_CREDENTIALS_JSON"
    GOOGLE_DRIVE_VOICE_INBOX_FOLDER_ID = "GOOGLE_DRIVE_VOICE_INBOX_FOLDER_ID"
    NOTES_INPUT_FOLDER_ID              = "NOTES_INPUT_FOLDER_ID"
    NOTES_PROCESSED_FOLDER_ID          = "NOTES_PROCESSED_FOLDER_ID"
    OPENAI_API_KEY                     = "OPENAI_API_KEY"
    TRANSCRIPTION_COG_API_KEY          = "TRANSCRIPTION_COG_API_KEY"
  }
  # Tuning the code has defaults for: set in Doppler to override.
  ssm_optional_parameters = {
    ARCHIVE_RETENTION_DAYS = "ARCHIVE_RETENTION_DAYS"
    ASANA_INBOX_SECTION_ID = "ASANA_INBOX_SECTION_ID"
    CLAUDE_MODEL           = "CLAUDE_MODEL"
    LLM_MODEL              = "LLM_MODEL"
    LLM_PROVIDER           = "LLM_PROVIDER"
    LOGGING_LEVEL          = "LOGGING_LEVEL"
    MIN_TRANSCRIPT_CHARS   = "MIN_TRANSCRIPT_CHARS"
    SENTRY_DSN             = "SENTRY_DSN"
    WHISPER_MODEL          = "WHISPER_MODEL"
  }
}

# Not a queue consumer: a tick every minute that lists the watched Drive
# folders and asks the API for what it finds. The API's dispatch claims turn
# the repeats into one job per file, so this remembers nothing and a missed
# tick is caught by the next. Replaces the always-on Railway watcher-cog.
module "watcher" {
  source = "./modules/scheduled-worker"

  name                     = "watcher"
  github_repo              = "mini-app-polis/watcher-cog"
  github_oidc_provider_arn = aws_iam_openid_connect_provider.github.arn
  alert_email              = local.alert_email
  api_base_url             = var.kaiano_api_base_url

  handler         = "watcher_cog.handler.lambda_handler"
  architecture    = "arm64"
  timeout_seconds = 50 # a tick is seconds; below the one-minute interval
  memory_mb       = 512

  schedule_interval_seconds = 60

  # On since 2026-09-26, after a hand-invoked tick queued live-history's
  # first sweep and a second answered it as already claimed. Overlap with
  # the Railway watcher is safe: the API's dispatch claims make the second
  # asker a no-op.
  enabled = true

  ssm_parameters = {
    CSV_SOURCE_FOLDER_ID               = "CSV_SOURCE_FOLDER_ID"
    GOOGLE_CREDENTIALS_JSON            = "GOOGLE_CREDENTIALS_JSON"
    GOOGLE_DRIVE_VOICE_INBOX_FOLDER_ID = "GOOGLE_DRIVE_VOICE_INBOX_FOLDER_ID"
    # The silence detector: the one alert that fires when nothing is
    # invoking the function at all. Required, not optional.
    HEALTHCHECKS_URL_WATCHER = "HEALTHCHECKS_URL_WATCHER"
    NOTES_INPUT_FOLDER_ID    = "NOTES_INPUT_FOLDER_ID"
    WATCHER_COG_API_KEY      = "WATCHER_COG_API_KEY"
  }
  ssm_optional_parameters = {
    LOG_LEVEL  = "LOG_LEVEL"
    SENTRY_DSN = "SENTRY_DSN"
  }
}
