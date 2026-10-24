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

  # A fleet pass is one job per repo, so 20 runs most of the fleet in one
  # wave. Each job posts back to one Railway container (single uvicorn
  # process, default 15-connection pool), but the posts are short. The
  # tighter limit in LLM mode is Anthropic's tokens per minute: 429s are
  # retried, but a retry still has to fit inside the 300s timeout.
  max_concurrency = 20

  # GITHUB_TOKEN is the name the code reads; its value is the fleet's one
  # read-only GitHub token, GITHUB_DASHBOARD_TOKEN.
  ssm_parameters = {
    EVALUATOR_COG_API_KEY = "EVALUATOR_COG_API_KEY"
    GITHUB_TOKEN          = "GITHUB_DASHBOARD_TOKEN"
  }
  ssm_optional_parameters = {
    ANTHROPIC_API_KEY = "ANTHROPIC_API_KEY"
    ANTHROPIC_MODEL   = "ANTHROPIC_MODEL"
    LOGGING_LEVEL     = "LOGGING_LEVEL"
    SENTRY_DSN_COGS   = "SENTRY_DSN_COGS"
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
  handler      = "deejay_cog.worker.lambda_handler"
  architecture = "x86_64"

  # The slowest run in four weeks was about 34s. A failing job holds the
  # FIFO queue for up to max_receive_count x (timeout + 60s), so this is
  # kept near what runs take rather than at Lambda's 900s ceiling.
  timeout_seconds = 300
  memory_mb       = 1024

  # Serialised: two sweeps of one Drive folder race to upload and archive
  # the same files. FIFO with one message group, so jobs queue without
  # being throttled; 3 receives is then three real failures.
  fifo                 = true
  reserved_concurrency = 1
  max_receive_count    = 3

  environment = {
    SPOTIPY_REDIRECT_URI  = "http://127.0.0.1:8888/callback"
    VDJ_HISTORY_FOLDER_ID = "1HGxEr5ocY9JLtXcJqDRIOD95rXU6QLUW"
  }

  ssm_parameters = {
    DEEJAY_COG_API_KEY      = "DEEJAY_COG_API_KEY"
    GOOGLE_CREDENTIALS_JSON = "GOOGLE_CREDENTIALS_JSON"
  }
  ssm_optional_parameters = {
    LOGGING_LEVEL             = "LOGGING_LEVEL"
    SENTRY_DSN_COGS           = "SENTRY_DSN_COGS"
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

  handler      = "transcription_cog.worker.lambda_handler"
  architecture = "arm64"

  # The slowest run in four weeks was about 2.4 min, but the timeout is set
  # by the worst case, not the typical run: transcription-cog budgets
  # 720 s of Whisper and Claude timeouts plus Drive and the task request for
  # one voice note. Below 900 s a slow but healthy note is killed mid-run and retried.
  timeout_seconds = 900
  memory_mb       = 512

  # One file per job, serialised. FIFO with one message group, as deejay.
  fifo                 = true
  reserved_concurrency = 1
  max_receive_count    = 3

  ssm_parameters = {
    ANTHROPIC_API_KEY                  = "ANTHROPIC_API_KEY"
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
    CLAUDE_MODEL           = "CLAUDE_MODEL"
    LLM_MODEL              = "LLM_MODEL"
    LLM_PROVIDER           = "LLM_PROVIDER"
    LOGGING_LEVEL          = "LOGGING_LEVEL"
    MIN_TRANSCRIPT_CHARS   = "MIN_TRANSCRIPT_CHARS"
    SENTRY_DSN_COGS        = "SENTRY_DSN_COGS"
    WHISPER_MODEL          = "WHISPER_MODEL"
  }
}

# The wiki curator's worker (wiki-curator-cog ADR-006). One job per
# message: link one source, consolidate named entities, or generate named
# entities' prose. The API enqueues a link when a source is composed (behind
# flags.wcs.wiki_jobs_enabled, off until switched on) and the follow-ons each
# job names; the worker reads and writes the wiki state through the API.
module "wiki_curator" {
  source = "./modules/cog-worker"

  name                     = "wiki-curator"
  github_repo              = "mini-app-polis/wiki-curator-cog"
  github_oidc_provider_arn = aws_iam_openid_connect_provider.github.arn
  alert_email              = local.alert_email
  api_base_url             = var.kaiano_api_base_url

  handler      = "wiki_curator_cog.worker.lambda_handler"
  architecture = "arm64"

  # A generate job is up to 25 entities, one model call each, one after
  # another; a link job is one source's statements in a call or two. The
  # worst case is the 25-entity job against a slow model, so 900 s, and the
  # worker stops itself 30 s short of it and returns the record.
  timeout_seconds = 900
  # The export and the three state documents are read whole, about 30 MB of
  # JSON in memory with the parsed copies.
  memory_mb = 1024

  # FIFO, and the API picks each job's message group by what it writes
  # (api-kaianolevine-com wiki_dispatch.group_for): consolidate and generate
  # share one group, so two never pay for one entity; link runs a group per
  # source and materialise spreads over a few page groups. This is the
  # ceiling on how many run at once across all groups. Every job starts by
  # reading the whole export from the API, and five of those at once got
  # 502s from it (2026-10-18), so it stays low: 2 is AWS's floor for a
  # mapping's maximum.
  fifo              = true
  max_concurrency   = 2
  max_receive_count = 3

  ssm_parameters = {
    ANTHROPIC_API_KEY        = "ANTHROPIC_API_KEY"
    WIKI_CURATOR_COG_API_KEY = "WIKI_CURATOR_COG_API_KEY"
  }
  ssm_optional_parameters = {
    LLM_MODEL       = "LLM_MODEL"
    LLM_PROVIDER    = "LLM_PROVIDER"
    LOGGING_LEVEL   = "LOGGING_LEVEL"
    SENTRY_DSN_COGS = "SENTRY_DSN_COGS"
  }
}

# The one writer to the task board. A source asks the API for a task
# (POST /v1/tasks) and the API enqueues it here; the worker composes the
# task, mints its id and creates it in Asana. It reads and writes nothing
# through the API but its run reports.
module "task_manager" {
  source = "./modules/cog-worker"

  name                     = "task-manager"
  github_repo              = "mini-app-polis/task-manager-cog"
  github_oidc_provider_arn = aws_iam_openid_connect_provider.github.arn
  alert_email              = local.alert_email
  api_base_url             = var.kaiano_api_base_url

  # Created after GitHub made immutable OIDC subjects the default, which a
  # repository cannot turn off: its workflows present the org's and the
  # repository's ids, not their names.
  github_oidc_subject = "repo:mini-app-polis@270520182/task-manager-cog@1427477351"

  handler      = "task_manager_cog.worker.lambda_handler"
  architecture = "arm64"

  # A job is a handful of Asana requests: look the task up, page the board's
  # names, resolve tags, create. Each has the client's 30 s timeout, so 120 s
  # covers several slow ones; the worker stops itself 20 s short of it.
  timeout_seconds = 120
  memory_mb       = 256

  # Serialised: ids are minted as the highest on the board plus one, which
  # is only safe one job at a time. FIFO with one message group, as deejay.
  fifo                 = true
  reserved_concurrency = 1
  max_receive_count    = 3

  # The hourly grooming sweep: every task waiting to be worked, checked
  # against the definition of ready. On the queue, so it never runs beside
  # a job creating a task.
  schedules = {
    sweep = {
      expression = "rate(1 hour)"
      body       = jsonencode({ type = "task.sweep", version = 1 })
    }
  }

  ssm_parameters = {
    ASANA_ACCESS_TOKEN       = "ASANA_ACCESS_TOKEN"
    ASANA_INBOX_PROJECT_ID   = "ASANA_INBOX_PROJECT_ID"
    ASANA_WORKSPACE_ID       = "ASANA_WORKSPACE_ID"
    TASK_MANAGER_COG_API_KEY = "TASK_MANAGER_COG_API_KEY"
  }
  ssm_optional_parameters = {
    ASANA_INBOX_SECTION_ID = "ASANA_INBOX_SECTION_ID"
    GROOM_AUTO_READY       = "GROOM_AUTO_READY"
    GROOM_DISPATCH         = "GROOM_DISPATCH"
    GROOM_DISPATCH_LIMIT   = "GROOM_DISPATCH_LIMIT"
    GROOM_SECTIONS         = "GROOM_SECTIONS"
    READY_SECTION          = "READY_SECTION"
    REFINING_SECTION       = "REFINING_SECTION"
    LOGGING_LEVEL          = "LOGGING_LEVEL"
    SENTRY_DSN_COGS        = "SENTRY_DSN_COGS"
    # The leaf-or-compound check and applying a groomer's split: shapes off
    # unless true; a split only reported unless GROOM_SPLIT_DRY_RUN is false.
    BLOCKED_SECTION          = "BLOCKED_SECTION"
    GROOM_SPLIT_DRY_RUN      = "GROOM_SPLIT_DRY_RUN"
    GROOM_SPLIT_MAX_CHILDREN = "GROOM_SPLIT_MAX_CHILDREN"
    GROOM_TASK_SHAPES        = "GROOM_TASK_SHAPES"
    # Agent dispatch at the end of the sweep: off unless AGENT_DISPATCH is
    # true. The agent GitHub App only starts the caller workflow in a
    # target repository; its key is optional so the sweep runs without it.
    AGENT_APP_CLIENT_ID       = "AGENT_APP_CLIENT_ID"
    AGENT_APP_PRIVATE_KEY     = "AGENT_APP_PRIVATE_KEY"
    AGENT_DISPATCH            = "AGENT_DISPATCH"
    AGENT_DRY_RUN             = "AGENT_DRY_RUN"
    AGENT_MODEL               = "AGENT_MODEL"
    AGENT_MONTHLY_CAP_USD     = "AGENT_MONTHLY_CAP_USD"
    AGENT_RUN_TIMEOUT_MINUTES = "AGENT_RUN_TIMEOUT_MINUTES"
    AGENT_TASK_CAP_USD        = "AGENT_TASK_CAP_USD"
    IN_PROGRESS_SECTION       = "IN_PROGRESS_SECTION"
    REVIEW_SECTION            = "REVIEW_SECTION"
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

  # One invocation per folder every minute, so a slow or failing folder
  # cannot spend the others' 50s or fail their tick. The names are
  # watcher-cog's get_watchers() names; an unknown one fails its invocation
  # loudly rather than watching nothing. All four ping the one Healthchecks
  # check, which only catches the schedule stopping; the error alarm below
  # is what notices a single folder failing.
  schedule_targets = {
    for name in ["dj-sets", "live-history", "wcs-notes", "voice-notes"] :
    name => { watcher = name }
  }

  # Ten failed ticks in a row, not 3 of 5: an API deploy or restart fails a
  # few ticks and the next tick catches up, so only a sustained failure pages.
  error_alarm_window    = 10
  error_alarm_threshold = 10

  # On since 2026-09-26, after a hand-invoked tick queued live-history's
  # first sweep and a second answered it as already claimed. Overlap with
  # the Railway watcher is safe: the API's dispatch claims make the second
  # asker a no-op.
  enabled = true

  ssm_parameters = {
    CSV_SOURCE_FOLDER_ID               = "CSV_SOURCE_FOLDER_ID"
    GOOGLE_CREDENTIALS_JSON            = "GOOGLE_CREDENTIALS_JSON"
    GOOGLE_DRIVE_VOICE_INBOX_FOLDER_ID = "GOOGLE_DRIVE_VOICE_INBOX_FOLDER_ID"
    LIVE_HISTORY_FOLDER_ID             = "LIVE_HISTORY_FOLDER_ID"
    # The silence detector: the one alert that fires when nothing is
    # invoking the function at all. Required, not optional.
    HEALTHCHECKS_URL_WATCHER = "HEALTHCHECKS_URL_WATCHER"
    NOTES_INPUT_FOLDER_ID    = "NOTES_INPUT_FOLDER_ID"
    WATCHER_COG_API_KEY      = "WATCHER_COG_API_KEY"
  }
  ssm_optional_parameters = {
    LOGGING_LEVEL   = "LOGGING_LEVEL"
    SENTRY_DSN_COGS = "SENTRY_DSN_COGS"
  }
}

module "task_groomer" {
  source = "./modules/cog-worker"

  name                     = "task-groomer"
  github_repo              = "mini-app-polis/task-groomer-cog"
  github_oidc_provider_arn = aws_iam_openid_connect_provider.github.arn
  alert_email              = local.alert_email
  api_base_url             = var.kaiano_api_base_url

  # Created with GitHub's immutable OIDC subjects, as task-manager-cog was.
  github_oidc_subject = "repo:mini-app-polis@270520182/task-groomer-cog@1428880997"

  handler      = "task_groomer_cog.worker.lambda_handler"
  architecture = "arm64"

  # A job is one model run of up to 8 rounds, each a Messages request that
  # can take tens of seconds, plus reading repositories as zipballs held in
  # memory. The worker stops itself 20 s short of the timeout.
  timeout_seconds = 600
  memory_mb       = 1024

  # A job is a paid run, and a redelivered job would pay again. Each message
  # is delivered once: a run that fails is reported by the cog and the task
  # waits for its next change. A crash outside the run goes straight to the
  # dead-letter queue, whose alarm says so.
  max_receive_count = 1

  # A standard queue: grooming one task does not wait on another. Two at a
  # time keeps the hourly batch (at most 5) quick without bursting the
  # model's rate limits. No reservation, so nothing is throttled into
  # spending its one delivery.
  max_concurrency = 2

  ssm_parameters = {
    ANTHROPIC_API_KEY        = "ANTHROPIC_API_KEY"
    TASK_GROOMER_COG_API_KEY = "TASK_GROOMER_COG_API_KEY"
  }
  ssm_optional_parameters = {
    GITHUB_TOKEN              = "GITHUB_DASHBOARD_TOKEN"
    GROOMER_MODEL             = "GROOMER_MODEL"
    GROOMER_MAX_ROUNDS        = "GROOMER_MAX_ROUNDS"
    GROOMER_MAX_INPUT_TOKENS  = "GROOMER_MAX_INPUT_TOKENS"
    GROOMER_MAX_OUTPUT_TOKENS = "GROOMER_MAX_OUTPUT_TOKENS"
    GROOMER_MONTHLY_CAP_USD   = "GROOMER_MONTHLY_CAP_USD"
    LOGGING_LEVEL             = "LOGGING_LEVEL"
    SENTRY_DSN_COGS           = "SENTRY_DSN_COGS"
    # Splitting a task into children: off unless true.
    GROOMER_SPLIT = "GROOMER_SPLIT"
  }
}
