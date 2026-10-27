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

  # Reads its own Doppler project, evaluator-cog (README.md, "Doppler
  # layout"); the names below say which vault value each one references.
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

  # Reads its own Doppler project, deejay-cog (README.md, "Doppler
  # layout"); the names below say which vault value each one references.
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

  # Reads its own Doppler project, transcription-cog (README.md, "Doppler
  # layout"); the names below say which vault value each one references.
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

# The wiki curator's worker (wiki-curator-cog ADR-0006). One job per
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

  # Reads its own Doppler project, wiki-curator-cog (README.md, "Doppler
  # layout"); the names below say which vault value each one references.
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

  # Reads its own Doppler project, task-manager-cog (README.md, "Doppler
  # layout"); the names below say which vault value each one references.
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
  # loudly rather than watching nothing, and scripts/check_watcher_names.py
  # fails CI on one before it ships. All four ping the one Healthchecks
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

  # Reads its own Doppler project, watcher-cog (README.md, "Doppler
  # layout"); the names below say which vault value each one references.
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

  # Reads its own Doppler project, task-groomer-cog (README.md, "Doppler
  # layout"); the names below say which vault value each one references.
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

# Rotates the fleet's secrets and records each rotation (rotator-cog). It
# writes new values into Doppler, so it holds Doppler tokens of its own,
# one per config it rotates, kept outside the prefix Doppler syncs (below).
# The API enqueues its jobs through the producer's `*-jobs` grant
# (account.tf), as for every cog.
module "rotator" {
  source = "./modules/cog-worker"

  name                     = "rotator"
  github_repo              = "mini-app-polis/rotator-cog"
  github_oidc_provider_arn = aws_iam_openid_connect_provider.github.arn
  alert_email              = local.alert_email
  api_base_url             = var.kaiano_api_base_url

  # Created with GitHub's immutable OIDC subjects, as task-manager-cog was.
  github_oidc_subject = "repo:mini-app-polis@270520182/rotator-cog@1433517907"

  handler      = "rotator_cog.worker.lambda_handler"
  architecture = "arm64"

  # A job is one secret: mint the new value and hand it over in Doppler in
  # two phases, each followed by waiting for Railway to show the value and
  # for the redeploys to run, then verify and record. Those waits are
  # minutes, so Lambda's ceiling.
  timeout_seconds = 900
  memory_mb       = 256

  # Serialised: two rotations writing the same Doppler config would race.
  # FIFO with one message group, as deejay. One delivery: a rotation that
  # fails partway has left something half-rotated that needs a person, so
  # it is dead-lettered and alarmed rather than tried again.
  fifo                 = true
  reserved_concurrency = 1
  max_receive_count    = 1

  # The daily sweep, one message per Doppler config the rotator holds a
  # token for: each rotates what is due in that config. Anything urgent is
  # asked for on demand through the API instead.
  schedules = {
    for config in keys(local.rotator_doppler_token_parameters) : "sweep-${config}" => {
      expression = "cron(0 14 * * ? *)"
      body       = jsonencode({ type = "rotation.sweep", version = 1, payload = { config = config } })
    }
  }

  # Where its Doppler and Railway tokens are: the names only, never the
  # values.
  environment = {
    DOPPLER_TOKEN_PRD_PARAMETER = local.rotator_doppler_token_parameters.prd
    DOPPLER_TOKEN_DEV_PARAMETER = local.rotator_doppler_token_parameters.dev
    RAILWAY_TOKEN_PRD_PARAMETER = local.rotator_railway_token_parameters.prd
    RAILWAY_TOKEN_DEV_PARAMETER = local.rotator_railway_token_parameters.dev

    # TURNSTILE_SECRET_KEY's rotation: the widget it belongs to, and where
    # the Cloudflare token that rotates it is. Neither identifier is secret.
    CLOUDFLARE_TURNSTILE_TOKEN_PARAMETER = local.rotator_cloudflare_turnstile_token_parameter
    CLOUDFLARE_ACCOUNT_ID                = var.cloudflare_account_id
    TURNSTILE_SITEKEY                    = cloudflare_turnstile_widget.kaiano_api.sitekey
  }

  # Reads its own Doppler project, rotator-cog (README.md, "Doppler
  # layout"); the names below say which vault value each one references.
  ssm_parameters = {
    ROTATOR_COG_API_KEY = "ROTATOR_COG_API_KEY"
  }
  ssm_optional_parameters = {
    LOGGING_LEVEL   = "LOGGING_LEVEL"
    SENTRY_DSN_COGS = "SENTRY_DSN_COGS"
    # The daily sweep rotates what is due only when this is true.
    ROTATOR_SWEEP_ROTATE = "ROTATOR_SWEEP_ROTATE"
    # It asks for a task per due manual secret only when this is true.
    ROTATOR_SWEEP_TASKS = "ROTATOR_SWEEP_TASKS"
  }
}

# The rotator's two Doppler tokens: one for the prd config, one for dev.
# Outside /mini-app-polis/, so neither Doppler's sync role nor any worker's
# grant on that prefix reaches them, and readable by the rotator's role
# alone (infra-plan's deny in ci.tf already covers them).
#
# Put by hand, not declared here: Terraform reads a parameter it manages
# back, decrypted, on every plan, and infra-plan may read none but the
# alert address. See the README.
locals {
  rotator_doppler_token_parameters = {
    prd = "/rotator/DOPPLER_TOKEN_PRD"
    dev = "/rotator/DOPPLER_TOKEN_DEV"
  }

  # The Railway tokens it redeploys the services that read a rotated secret
  # at boot with: project tokens, and a project token reaches one
  # environment, so one per config as for Doppler (prd is the production
  # environment, dev development). Values of the rotator's own in its
  # Doppler project's prd config, not references into the vault, so they
  # reach no other consumer; that config's sync puts them here. Not in the
  # module's ssm_parameters: the worker reads them when it redeploys, and
  # they never go in its environment.
  rotator_railway_token_parameters = {
    prd = "/mini-app-polis/rotator-cog/prd/ROTATOR_RAILWAY_TOKEN_PRD"
    dev = "/mini-app-polis/rotator-cog/prd/ROTATOR_RAILWAY_TOKEN_DEV"
  }

  # The Cloudflare token it rotates TURNSTILE_SECRET_KEY with, whose only
  # permission is Turnstile Sites: Edit. A value of the rotator's own, like
  # the Railway tokens, read by path when it rotates.
  rotator_cloudflare_turnstile_token_parameter = "/mini-app-polis/rotator-cog/prd/ROTATOR_CLOUDFLARE_TURNSTILE_TOKEN"
}

# Those parameters, by name, and nothing else outside the module's own
# grant. No KMS grant: they are SecureStrings under the AWS-managed aws/ssm
# key, as the synced ones are.
data "aws_iam_policy_document" "rotator_doppler_token" {
  statement {
    actions = ["ssm:GetParameter", "ssm:GetParameters"]
    resources = [
      for name in concat(
        values(local.rotator_doppler_token_parameters),
        values(local.rotator_railway_token_parameters),
        [local.rotator_cloudflare_turnstile_token_parameter],
      ) :
      "arn:aws:ssm:${var.region}:${data.aws_caller_identity.current.account_id}:parameter${name}"
    ]
  }
}

resource "aws_iam_role_policy" "rotator_doppler_token" {
  name   = "rotator-doppler-token"
  role   = module.rotator.worker_role_name
  policy = data.aws_iam_policy_document.rotator_doppler_token.json
}

# The IAM users whose access keys the rotator rotates, by name. rotator-cog's
# secrets/inventory.yaml owns which they are (the iam_user of each
# aws-access-key entry); scripts/check_rotator_iam_users.py fails CI when
# this differs from it. Each is a user this root declares for one Railway
# service's long-lived key, none of them an identity that can change IAM.
locals {
  rotator_iam_users = {
    "db-backup-reader"   = aws_iam_user.db_backup_reader
    "db-backup-writer"   = aws_iam_user.db_backup_writer
    "db-poller"          = aws_iam_user.db_poller
    "evaluator-producer" = aws_iam_user.producer
  }
}

# Mint, deactivate, delete and list those users' access keys, on their ARNs
# alone: nothing over any other user, nor over its own role or policies.
# Holding this, the rotator can act as any of them, so each user's own
# policy is the bound on what that means.
data "aws_iam_policy_document" "rotator_access_keys" {
  statement {
    actions = [
      "iam:CreateAccessKey",
      "iam:DeleteAccessKey",
      "iam:ListAccessKeys",
      "iam:UpdateAccessKey",
    ]
    resources = [for user in values(local.rotator_iam_users) : user.arn]
  }
}

resource "aws_iam_role_policy" "rotator_access_keys" {
  name   = "rotator-access-keys"
  role   = module.rotator.worker_role_name
  policy = data.aws_iam_policy_document.rotator_access_keys.json

  lifecycle {
    # The check script compares the names; this keeps each name the user's.
    precondition {
      condition     = alltrue([for name, user in local.rotator_iam_users : user.name == name])
      error_message = "A key of local.rotator_iam_users is not the name of the aws_iam_user it maps to."
    }
  }
}
