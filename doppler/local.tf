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
