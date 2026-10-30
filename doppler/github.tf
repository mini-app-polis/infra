# GitHub Actions: every secret and variable a workflow reads, synced from
# Doppler rather than set by hand.
#
# A repository's values are in an environment of its project, `ci`, synced
# to the repository: its secrets as Actions secrets and its unmasked ones
# (the variables below) as Actions variables. A GitHub environment's values
# (infra's `production`) are an environment of their own, `ci-<name>`.
#
# What the whole organisation reads (CI_VALIDATOR_API_KEY, the promote and
# agent GitHub Apps, AWS_REGION) is the github-org project's `ci` config,
# synced to organisation secrets and variables visible to every repository:
# the organisation's repositories are public, so "private" would reach none.
#
# A reference takes its visibility from the secret it points at, so a
# variable's value must be unmasked in the vault itself; one that is masked
# there syncs as a secret, whatever its visibility here.
#
# Doppler also syncs its own DOPPLER_CONFIG, DOPPLER_ENVIRONMENT and
# DOPPLER_PROJECT as variables wherever variables are synced. Nothing reads
# them.
#
# Each source names a vault config and secret, "prd.NAME" or "dev.NAME".
# A value that comes from this repository's own resources (a role ARN, a
# function name) is not a secret and has no place in the vault: it is a
# doppler_secret below, which keeps it in this root's state.

locals {
  github_connection = "57f3cee1-f4d9-45c3-a3a7-528bedda0043"

  root = data.terraform_remote_state.infra.outputs

  # The Lambda workers' deploy variables, from the root's outputs.
  worker_deploy_variables = merge(
    {
      for name, cog in local.root.cogs : "${name}-cog" => {
        AWS_DEPLOY_ROLE_ARN = cog.AWS_DEPLOY_ROLE_ARN
        AWS_FUNCTION_NAME   = cog.AWS_FUNCTION_NAME
      }
    },
    {
      "watcher-cog" = {
        AWS_DEPLOY_ROLE_ARN = local.root.watcher.AWS_DEPLOY_ROLE_ARN
        AWS_FUNCTION_NAME   = local.root.watcher.AWS_FUNCTION_NAME
      }
    },
  )

  # deejay-cog deploys a second function, its fingerprint function, through
  # a role of its own; until the root has applied it there is nothing to add.
  fingerprint_deploy_variables = try({
    AWS_FINGERPRINT_DEPLOY_ROLE_ARN = local.root.deejay_fingerprint.AWS_DEPLOY_ROLE_ARN
    AWS_FINGERPRINT_FUNCTION_NAME   = local.root.deejay_fingerprint.AWS_FUNCTION_NAME
  }, {})

  # Per sync: the repository, the GitHub environment if any, its secrets and
  # variables (name → vault source), and values from this repository.
  github_targets = merge(
    {
      for repo, variables in local.worker_deploy_variables : repo => {
        repo        = repo
        environment = null
        secrets = {
          for name, source in { WIKI_CURATOR_DEPLOY_API_KEY = "prd.WIKI_CURATOR_DEPLOY_API_KEY" } :
          name => source if repo == "wiki-curator-cog"
        }
        variables = {}
        literals  = repo == "deejay-cog" ? merge(variables, local.fingerprint_deploy_variables) : variables
      }
    },
    {
      "api-deejaytools" = {
        repo        = "api-deejaytools"
        environment = null
        secrets     = { RAILWAY_TOKEN = "prd.RAILWAY_TOKEN" }
        variables = {
          API_URL_DEVELOPMENT = "prd.DEEJAYTOOLS_API_DEV"
          API_URL_PRODUCTION  = "prd.DEEJAYTOOLS_API"
        }
        literals = {}
      }
      "api-kaianolevine-com" = {
        repo        = "api-kaianolevine-com"
        environment = null
        secrets     = { RAILWAY_TOKEN = "prd.RAILWAY_TOKEN" }
        variables   = {}
        literals    = {}
      }
      "db-ops" = {
        repo        = "db-ops"
        environment = null
        secrets     = { RAILWAY_TOKEN = "prd.RAILWAY_TOKEN" }
        variables   = {}
        literals    = {}
      }
      "common-python-utils" = {
        repo        = "common-python-utils"
        environment = null
        # The contract suite runs against the development API, with its key.
        secrets   = { CONTRACT_SUITE_API_KEY = "dev.CONTRACT_SUITE_API_KEY" }
        variables = { CONTRACT_API_URL = "prd.KAIANO_API_BASE_URL_DEV" }
        literals  = {}
      }
      "deejaytools-com" = {
        repo        = "deejaytools-com"
        environment = null
        secrets     = { CONTRACT_CLERK_SECRET_KEY = "dev.DEEJAYTOOLS_CLERK_SECRET_KEY" }
        variables = {
          CONTRACT_API_URL = "prd.DEEJAYTOOLS_API_DEV"
          CONTRACT_USER_ID = "prd.CONTRACT_USER_ID"
        }
        literals = {}
      }
      "ecosystem-standards" = {
        repo        = "ecosystem-standards"
        environment = null
        secrets = {
          ECOSYSTEM_STANDARDS_API_KEY     = "prd.ECOSYSTEM_STANDARDS_API_KEY"
          ECOSYSTEM_STANDARDS_API_KEY_DEV = "dev.ECOSYSTEM_STANDARDS_API_KEY"
        }
        variables = { KAIANO_API_BASE_URL = "prd.KAIANO_API_BASE_URL" }
        literals  = {}
      }
      "infra" = {
        repo        = "infra"
        environment = null
        secrets = {
          CLOUDFLARE_API_TOKEN_READ = "prd.CLOUDFLARE_API_TOKEN_READ"
          DOPPLER_TOKEN_PAGES       = "prd.DOPPLER_TOKEN_PAGES"
        }
        variables = {}
        literals  = local.root.ci_roles
      }
      "infra/production" = {
        repo        = "infra"
        environment = "production"
        secrets     = { CLOUDFLARE_API_TOKEN = "prd.CLOUDFLARE_API_TOKEN" }
        variables   = {}
        literals    = {}
      }
      "wcs-wiki" = {
        repo        = "wcs-wiki"
        environment = null
        secrets     = { WIKI_CURATOR_COG_API_KEY = "prd.WIKI_CURATOR_COG_API_KEY" }
        variables   = {}
        literals    = {}
      }
      "website-astro-wcs" = {
        repo        = "website-astro-wcs"
        environment = null
        secrets     = {}
        variables   = { PUBLIC_CLERK_PUBLISHABLE_KEY = "prd.PUBLIC_CLERK_PUBLISHABLE_KEY" }
        literals    = {}
      }
      "website-astro-wcsmn" = {
        repo        = "website-astro-wcsmn"
        environment = null
        secrets     = {}
        variables   = { GOOGLE_CALENDAR_PUBLIC_API_KEY = "prd.GOOGLE_CALENDAR_PUBLIC_API_KEY" }
        literals    = {}
      }
    },
  )

  # Each target's Doppler environment, in the project named for its
  # repository.
  github_configs = {
    for key, target in local.github_targets : key => {
      project = target.repo
      slug    = target.environment == null ? "ci" : "ci-${target.environment}"
      name    = target.environment == null ? "GitHub Actions" : "GitHub Actions ${target.environment}"
    }
  }

  # What the organisation reads, in github-org's ci config.
  github_organisation = {
    secrets = {
      AGENT_ANTHROPIC_API_KEY = "prd.AGENT_ANTHROPIC_API_KEY"
      AGENT_APP_CLIENT_ID     = "prd.AGENT_APP_CLIENT_ID"
      AGENT_APP_PRIVATE_KEY   = "prd.AGENT_APP_PRIVATE_KEY"
      CI_VALIDATOR_API_KEY    = "prd.CI_VALIDATOR_API_KEY"
      PROMOTE_APP_CLIENT_ID   = "prd.PROMOTE_APP_CLIENT_ID"
      PROMOTE_APP_PRIVATE_KEY = "prd.PROMOTE_APP_PRIVATE_KEY"
      TASK_AGENT_API_KEY      = "prd.TASK_AGENT_API_KEY"
    }
    variables = { AWS_REGION = "prd.AWS_REGION" }
  }

  # Workflow runs started by Dependabot see the organisation's Dependabot
  # secrets, not its Actions secrets, so the promote and agent workflows'
  # own credentials are there too. The sync was made in the dashboard, from
  # agent-github's dependabot config (the provider has no Dependabot sync);
  # its values are references like everyone else's, so a rotation reaches it.
  github_dependabot = {
    for name in [
      "AGENT_ANTHROPIC_API_KEY",
      "AGENT_APP_CLIENT_ID",
      "AGENT_APP_PRIVATE_KEY",
      "PROMOTE_APP_CLIENT_ID",
      "PROMOTE_APP_PRIVATE_KEY",
      "TASK_AGENT_API_KEY",
    ] : name => local.github_organisation.secrets[name]
  }

  # Repositories without a project of their own yet, and the organisation's.
  github_projects = setunion(
    setsubtract(
      toset([for target in local.github_targets : target.repo]),
      toset(keys(local.parameter_store_consumers)),
    ),
    toset(["github-org"]),
  )

  # References for scripts/doppler_references.py: secrets masked, variables
  # unmasked, so the sync makes them Actions variables.
  github_references = concat(
    [
      for key, target in local.github_targets : {
        project = local.github_configs[key].project
        config  = local.github_configs[key].slug
        refs = merge(
          { for name, source in target.secrets : name => { ref = "$${${lookup(local.vault_home, split(".", source)[1], local.vault_settings)}.${source}}", visibility = "masked" } },
          { for name, source in target.variables : name => { ref = "$${${lookup(local.vault_home, split(".", source)[1], local.vault_settings)}.${source}}", visibility = "unmasked" } },
        )
      }
    ],
    [
      {
        project = "github-org"
        config  = "ci"
        refs = merge(
          { for name, source in local.github_organisation.secrets : name => { ref = "$${${lookup(local.vault_home, split(".", source)[1], local.vault_settings)}.${source}}", visibility = "masked" } },
          { for name, source in local.github_organisation.variables : name => { ref = "$${${lookup(local.vault_home, split(".", source)[1], local.vault_settings)}.${source}}", visibility = "unmasked" } },
        )
      },
      {
        project = "agent-github"
        config  = "dependabot"
        refs    = { for name, source in local.github_dependabot : name => { ref = "$${${lookup(local.vault_home, split(".", source)[1], local.vault_settings)}.${source}}", visibility = "masked" } }
      },
    ],
  )
}

locals {
  # Every project this root makes, by name.
  project_names = merge(
    { for key, project in doppler_project.consumer : key => project.name },
    { for key, project in doppler_project.repository : key => project.name },
  )
}

# deejaytools-com's project was made in the dashboard, for local runs.
import {
  to = doppler_project.repository["deejaytools-com"]
  id = "deejaytools-com"
}

resource "doppler_project" "repository" {
  for_each = local.github_projects

  name        = each.key
  description = "${each.key}: references into ${local.vault_secrets} and ${local.vault_settings}, under the names its code and workflows read. Layout in mini-app-polis/infra doppler/."
}

resource "doppler_environment" "github_org" {
  project          = doppler_project.repository["github-org"].name
  slug             = "ci"
  name             = "GitHub Actions"
  personal_configs = false
}

resource "doppler_secrets_sync_github_actions" "organisation" {
  integration = local.github_connection
  project     = doppler_environment.github_org.project
  config      = doppler_environment.github_org.slug

  sync_target                = "org"
  org_scope                  = "all"
  sync_unmasked_as_variables = true

  delete_behavior = "delete_from_target"
}

resource "doppler_environment" "github" {
  for_each = local.github_configs

  project          = local.project_names[each.value.project]
  slug             = each.value.slug
  name             = each.value.name
  personal_configs = false
}

# Values from this repository's own resources, unmasked, so they sync as
# Actions variables.
resource "doppler_secret" "github" {
  for_each = merge([
    for key, target in local.github_targets : {
      for name, value in target.literals : "${key}/${name}" => {
        config = key
        name   = name
        value  = value
      }
    }
  ]...)

  project    = doppler_environment.github[each.value.config].project
  config     = doppler_environment.github[each.value.config].slug
  name       = each.value.name
  value      = each.value.value
  visibility = "unmasked"
}

resource "doppler_secrets_sync_github_actions" "repository" {
  for_each = local.github_targets

  integration = local.github_connection
  project     = doppler_environment.github[each.key].project
  config      = doppler_environment.github[each.key].slug

  sync_target                = "repo"
  repo_name                  = each.value.repo
  environment_name           = each.value.environment
  sync_unmasked_as_variables = true

  delete_behavior = "delete_from_target"
}
