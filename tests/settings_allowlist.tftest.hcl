# SETTINGS_ALLOWLIST as modules/cog-worker and modules/scheduled-worker
# derive it: a setting's name is in it, a secret's is not, and it holds
# names only. Planned against mocked providers, so it reads nothing from
# AWS:
#
#   terraform init && terraform test

mock_provider "aws" {}
mock_provider "archive" {}

variables {
  github_oidc_provider_arn = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
  alert_email              = "alerts@example.com"
  api_base_url             = "https://api.example.com"
  architecture             = "arm64"
  timeout_seconds          = 30
  memory_mb                = 256

  # As cogs.tf passes them: vault names that are not settings.
  non_settings_names = ["EXAMPLE_COG_API_KEY", "GITHUB_DASHBOARD_TOKEN", "SPOTIPY_REFRESH_TOKEN"]

  ssm_parameters = {
    EXAMPLE_COG_API_KEY = "EXAMPLE_COG_API_KEY"
    LIVE_FOLDER_ID      = "LIVE_FOLDER_ID"
  }
  ssm_optional_parameters = {
    # Named for the code, referencing a secret: a secret by its vault name.
    GITHUB_TOKEN          = "GITHUB_DASHBOARD_TOKEN"
    LOGGING_LEVEL         = "LOGGING_LEVEL"
    SPOTIPY_REFRESH_TOKEN = "SPOTIPY_REFRESH_TOKEN"
  }
}

run "cog_worker" {
  command = plan

  module {
    source = "./modules/cog-worker"
  }

  variables {
    name            = "example"
    github_repo     = "mini-app-polis/example-cog"
    handler         = "example_cog.worker.lambda_handler"
    max_concurrency = 2
  }

  assert {
    condition     = output.settings_allowlist == "LIVE_FOLDER_ID,LOGGING_LEVEL"
    error_message = "SETTINGS_ALLOWLIST is the sorted settings names: ${output.settings_allowlist}"
  }

  assert {
    condition     = length(setintersection(toset(split(",", output.settings_allowlist)), toset(["EXAMPLE_COG_API_KEY", "GITHUB_TOKEN", "SPOTIPY_REFRESH_TOKEN"]))) == 0
    error_message = "A name whose value is not in mini-app-polis-settings is in SETTINGS_ALLOWLIST."
  }

  assert {
    condition     = alltrue([for name in split(",", output.settings_allowlist) : can(regex("^[A-Z][A-Z0-9_]*$", name))])
    error_message = "SETTINGS_ALLOWLIST holds something other than names."
  }

  assert {
    condition     = aws_lambda_function.worker.environment[0].variables["SETTINGS_ALLOWLIST"] == output.settings_allowlist
    error_message = "The function's SETTINGS_ALLOWLIST is not the module's."
  }
}

run "scheduled_worker" {
  command = plan

  module {
    source = "./modules/scheduled-worker"
  }

  variables {
    name        = "example-tick"
    github_repo = "mini-app-polis/example-tick-cog"
    handler     = "example_tick_cog.handler.lambda_handler"
  }

  assert {
    condition     = output.settings_allowlist == "LIVE_FOLDER_ID,LOGGING_LEVEL"
    error_message = "SETTINGS_ALLOWLIST is the sorted settings names: ${output.settings_allowlist}"
  }

  assert {
    condition     = length(setintersection(toset(split(",", output.settings_allowlist)), toset(["EXAMPLE_COG_API_KEY", "GITHUB_TOKEN", "SPOTIPY_REFRESH_TOKEN"]))) == 0
    error_message = "A name whose value is not in mini-app-polis-settings is in SETTINGS_ALLOWLIST."
  }

  assert {
    condition     = aws_lambda_function.worker.environment[0].variables["SETTINGS_ALLOWLIST"] == output.settings_allowlist
    error_message = "The function's SETTINGS_ALLOWLIST is not the module's."
  }
}
