# Local runs. Each repository's doppler.yaml pins its own project's dev
# config, so `doppler run` locally sees the names its code reads and no
# others. A worker's and a Railway service's dev configs are declared with
# their deployed ones (main.tf, railway.tf). A repository whose project
# exists only for GitHub Actions gets its dev config here: the names its
# .env.example requires, and ENVIRONMENT, from the vault's dev.

locals {
  local_dev = {
    "common-python-utils" = [
      "ANTHROPIC_API_KEY",
      "DISCORD_WEBHOOK_URL_ACTIVITY",
      "DISCORD_WEBHOOK_URL_DEFAULT",
      "DISCORD_WEBHOOK_URL_ERRORS",
      "DISCORD_WEBHOOK_URL_RUNS",
      "ENVIRONMENT",
      "GOOGLE_CREDENTIALS_JSON",
      "KAIANO_API_BASE_URL_DEV",
      "SPOTIPY_CLIENT_ID",
      "SPOTIPY_CLIENT_SECRET",
      "SPOTIPY_REFRESH_TOKEN",
    ]
  }

  local_dev_references = [
    for project, names in local.local_dev : {
      project = project
      config  = "dev"
      refs = {
        for name in names : name => {
          ref        = contains(local.spotify_names, name) ? "$${${local.spotify}.prd.${name}}" : "$${${local.vault}.dev.${name}}"
          visibility = null
        }
      }
    }
  ]
}

resource "doppler_environment" "local_dev" {
  for_each = local.local_dev

  project          = local.project_names[each.key]
  slug             = "dev"
  name             = local.environments["dev"]
  personal_configs = false
}

# The owner's working sessions. owner-session is read only with the owner's
# own Doppler login and syncs nowhere: it holds the keys a session on the
# workstation signs in to the API with (common-python-utils' file-task as
# claude-session, rotator-cog's rotate.py as owner-console), and what the
# API client needs to find the API. prd reads the vault's prd, dev its dev.

locals {
  owner_session = {
    prd = {
      CLAUDE_SESSION_API_KEY = "prd.CLAUDE_SESSION_API_KEY"
      ENVIRONMENT            = "prd.ENVIRONMENT"
      KAIANO_API_BASE_URL    = "prd.KAIANO_API_BASE_URL"
      OWNER_CONSOLE_API_KEY  = "prd.OWNER_CONSOLE_API_KEY"
    }
    dev = {
      CLAUDE_SESSION_API_KEY  = "dev.CLAUDE_SESSION_API_KEY"
      ENVIRONMENT             = "dev.ENVIRONMENT"
      KAIANO_API_BASE_URL_DEV = "dev.KAIANO_API_BASE_URL_DEV"
      OWNER_CONSOLE_API_KEY   = "dev.OWNER_CONSOLE_API_KEY"
    }
  }

  owner_session_references = [
    for config, names in local.owner_session : {
      project = doppler_project.owner_session.name
      config  = config
      refs = {
        for name, source in names : name => {
          ref        = "$${${local.vault}.${source}}"
          visibility = null
        }
      }
    }
  ]
}

resource "doppler_project" "owner_session" {
  name        = "owner-session"
  description = "The owner's working sessions: references into ${local.vault}, read only with the owner's login, synced nowhere. Layout in mini-app-polis/infra doppler/."
}

resource "doppler_environment" "owner_session" {
  for_each = local.owner_session

  project          = doppler_project.owner_session.name
  slug             = each.key
  name             = local.environments[each.key]
  personal_configs = false
}
