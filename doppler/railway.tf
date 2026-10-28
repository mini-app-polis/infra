# Railway: each service reads its own Doppler config, synced to the service
# itself rather than to the environment's shared variables, so Railway holds
# only what each service reads.
#
# A service's config is in the project named for the repository that
# deploys it: api-kaianolevine-com and api-deejaytools each have prd and
# dev; db-ops has a root prd holding what all three of its crons read and a
# branch config per cron (prd_poller, prd_backup, prd_drill), which inherits
# the root's, and a dev root for local runs. The syncs themselves are made
# in the dashboard: the provider has no Railway sync resource.
#
# The names are copies of what each repository's .railway/railway.ts
# declares (its SHARED list, or db-ops' common and per-service lists),
# which owns them. A name added there is added here in the same change.
#
# Every NAME_PREVIOUS a service accepts is referenced too. The vault always
# holds those slots, empty while no rotation is in progress (rotator-cog
# ADR-0005), because a reference to a secret that does not exist is
# refused.

locals {
  machine_keys = [
    "CI_VALIDATOR_API_KEY",
    "DB_OPS_API_KEY",
    "DEEJAY_COG_API_KEY",
    "ECOSYSTEM_STANDARDS_API_KEY",
    "EVALUATOR_COG_API_KEY",
    "OPS_NOTIFIER_API_KEY",
    "ROTATOR_COG_API_KEY",
    "TASK_AGENT_API_KEY",
    "TASK_GROOMER_COG_API_KEY",
    "TASK_MANAGER_COG_API_KEY",
    "TRANSCRIPTION_COG_API_KEY",
    "WATCHER_COG_API_KEY",
    "WIKI_CURATOR_COG_API_KEY",
    "WIKI_CURATOR_DEPLOY_API_KEY",
  ]

  api_kaianolevine_com = concat(
    [
      "ANTHROPIC_API_KEY",
      "AWS_REGION",
      "BREVO_API_KEY",
      "CLERK_ISSUER",
      "CLERK_JWKS_URL",
      "CONTACT_FROM_EMAIL",
      "CONTACT_TO_EMAIL",
      "CORS_ORIGINS",
      "DISCORD_WEBHOOK_URL_ACTIVITY",
      "DISCORD_WEBHOOK_URL_DEFAULT",
      "DISCORD_WEBHOOK_URL_ERRORS",
      "DISCORD_WEBHOOK_URL_RUNS",
      "DOPPLER_WEBHOOK_SECRET",
      "DOPPLER_WEBHOOK_SECRET_PREVIOUS",
      "ENVIRONMENT",
      "EVALUATION_QUEUE_PRODUCER_KEY_ID",
      "EVALUATION_QUEUE_PRODUCER_SECRET",
      "GH_TOKEN",
      "GITHUB_ACTIONS_TOKEN",
      "GITHUB_DASHBOARD_TOKEN",
      "GITHUB_TOKEN",
      "GITHUB_WEBHOOK_SECRET",
      "GITHUB_WEBHOOK_SECRET_PREVIOUS",
      "GOOGLE_CREDENTIALS_JSON",
      "LOGGING_LEVEL",
      "OPENAI_API_KEY",
      "RESUME_FILE_ID",
      "SENTRY_DSN_APIS",
      "SIGNAL_CI_BRANCHES",
      "SPOTIPY_CLIENT_ID",
      "SPOTIPY_CLIENT_SECRET",
      "TURNSTILE_SECRET_KEY",
      "KAIANO_API_BASE_URL",
    ],
    local.machine_keys,
    [for key in local.machine_keys : "${key}_PREVIOUS"],
  )

  api_deejaytools = [
    "AWS_REGION",
    "BREVO_API_KEY",
    "DEEJAYTOOLS_CLERK_ISSUER",
    "DEEJAYTOOLS_CLERK_JWKS_URL",
    "DEEJAYTOOLS_CORS_ORIGINS",
    "DISCORD_WEBHOOK_URL_ACTIVITY",
    "DISCORD_WEBHOOK_URL_ERRORS",
    "ENVIRONMENT",
    "EVALUATION_QUEUE_PRODUCER_KEY_ID",
    "EVALUATION_QUEUE_PRODUCER_SECRET",
    "GOOGLE_CREDENTIALS_JSON",
    "GOOGLE_DRIVE_PARENT_FOLDER_ID",
    "LOGGING_LEVEL",
    "SENTRY_DSN_APIS",
    "TICK_SECRET",
    "TICK_SECRET_PREVIOUS",
  ]

  db_ops_common = [
    "AWS_REGION",
    "DB_OPS_API_KEY",
    "ENVIRONMENT",
    "KAIANO_API_BASE_URL",
    "LOGGING_LEVEL",
    "SENTRY_DSN_COGS",
  ]

  db_ops_crons = {
    poller = [
      "DB_POLLER_AWS_ACCESS_KEY_ID",
      "DB_POLLER_AWS_SECRET_ACCESS_KEY",
      "DB_POLLER_DATABASE_URL_DEEJAYTOOLS",
      "DB_POLLER_DATABASE_URL_KAIANOLEVINE",
    ]
    backup = [
      "DB_BACKUP_AWS_ACCESS_KEY_ID",
      "DB_BACKUP_AWS_SECRET_ACCESS_KEY",
      "DB_BACKUP_BUCKET",
      "DB_BACKUP_DATABASE_URL_DEEJAYTOOLS",
      "DB_BACKUP_DATABASE_URL_KAIANOLEVINE",
      "HEALTHCHECKS_URL_DB_BACKUP",
    ]
    drill = [
      "DB_BACKUP_BUCKET",
      "DB_DRILL_AWS_ACCESS_KEY_ID",
      "DB_DRILL_AWS_SECRET_ACCESS_KEY",
      "DB_DRILL_DATABASE_URL_DEEJAYTOOLS",
      "DB_DRILL_DATABASE_URL_KAIANOLEVINE",
      "DB_DRILL_RAILWAY_TOKEN",
    ]
  }

  # Per project and config, the names it holds, each a reference to the
  # same name in the vault's config of the same environment.
  railway_configs = {
    "api-kaianolevine-com" = {
      # The Spotify re-auth runs against production only.
      prd = concat(local.api_kaianolevine_com, ["DOPPLER_SPOTIFY_WRITE_TOKEN", "SPOTIFY_OWNER_USER_ID"])
      # Development's API address is suffixed _DEV (mini_app_polis.environment),
      # and the development-only machine is keyed here alone.
      dev = concat(local.api_kaianolevine_com, [
        "KAIANO_API_BASE_URL_DEV",
        "CONTRACT_SUITE_API_KEY",
        "CONTRACT_SUITE_API_KEY_PREVIOUS",
      ])
    }
    "api-deejaytools" = {
      prd = local.api_deejaytools
      dev = local.api_deejaytools
    }
    "db-ops" = merge(
      { prd = local.db_ops_common },
      { for cron, names in local.db_ops_crons : "prd_${cron}" => names },
      { dev = distinct(concat(local.db_ops_common, flatten(values(local.db_ops_crons)))) },
    )
  }
}

resource "doppler_environment" "railway" {
  for_each = {
    for pair in setproduct(keys(local.railway_configs), keys(local.environments)) :
    "${pair[0]}/${pair[1]}" => { project = pair[0], slug = pair[1] }
  }

  project          = local.project_names[each.value.project]
  slug             = each.value.slug
  name             = local.environments[each.value.slug]
  personal_configs = false
}

# db-ops' crons: each a branch of its prd, inheriting the root's names.
resource "doppler_config" "db_ops_cron" {
  for_each = local.db_ops_crons

  project     = doppler_environment.railway["db-ops/prd"].project
  environment = doppler_environment.railway["db-ops/prd"].slug
  name        = "prd_${each.key}"
}

locals {
  railway_references = flatten([
    for project, configs in local.railway_configs : [
      for config, names in configs : {
        project = project
        config  = config
        refs = {
          for name in names :
          name => { ref = "$${${local.vault}.${split("_", config)[0]}.${name}}", visibility = null }
        }
      }
    ]
  ])
}
