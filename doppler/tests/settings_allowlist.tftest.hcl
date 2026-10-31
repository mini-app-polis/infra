# Each Railway config's SETTINGS_ALLOWLIST (railway.tf): a setting's name is
# in it, a secret's never, a db-ops cron's includes what it inherits from
# its root, and it holds names only. Planned against a mocked provider and
# the root's outputs stubbed, so it reads nothing from Doppler or S3:
#
#   terraform -chdir=doppler init -backend=false && terraform -chdir=doppler test

mock_provider "doppler" {}

override_data {
  target = data.terraform_remote_state.infra
  values = {
    outputs = {
      doppler_consumers = {}
      cogs              = {}
      ci_roles          = {}
      watcher = {
        AWS_DEPLOY_ROLE_ARN = "arn:aws:iam::123456789012:role/watcher-deploy"
        AWS_FUNCTION_NAME   = "watcher-worker"
      }
    }
  }
}

run "railway_settings_allowlists" {
  command = plan

  assert {
    condition     = contains(split(",", output.settings_allowlists["api-kaianolevine-com/prd"]), "CORS_ORIGINS")
    error_message = "A setting api-kaianolevine-com reads is missing from its SETTINGS_ALLOWLIST."
  }

  assert {
    condition     = !contains(split(",", output.settings_allowlists["api-kaianolevine-com/prd"]), "ANTHROPIC_API_KEY")
    error_message = "A secret is in api-kaianolevine-com's SETTINGS_ALLOWLIST."
  }

  assert {
    condition     = alltrue([for name in ["DB_BACKUP_BUCKET", "LOGGING_LEVEL"] : contains(split(",", output.settings_allowlists["db-ops/prd_backup"]), name)])
    error_message = "db-ops' backup cron's SETTINGS_ALLOWLIST lacks its own or its root's settings."
  }

  assert {
    condition     = alltrue([for list in values(output.settings_allowlists) : length(setintersection(toset(split(",", list)), toset(jsondecode(file("vault_secret_names.tf.json")).locals.vault_secret_names))) == 0])
    error_message = "A name in mini-app-polis-secrets is in a SETTINGS_ALLOWLIST."
  }

  assert {
    condition     = alltrue([for list in values(output.settings_allowlists) : alltrue([for name in split(",", list) : can(regex("^[A-Z][A-Z0-9_]*$", name))])])
    error_message = "A SETTINGS_ALLOWLIST holds something other than names."
  }

  assert {
    condition     = alltrue([for list in values(output.settings_allowlists) : join(",", sort(split(",", list))) == list])
    error_message = "A SETTINGS_ALLOWLIST is not sorted."
  }

  assert {
    condition     = doppler_secret.settings_allowlist["db-ops/prd_backup"].config == "prd_backup"
    error_message = "db-ops' backup cron's SETTINGS_ALLOWLIST is not in its own branch config."
  }
}
