# Doppler's layout: a project per consumer, holding only what that consumer
# reads, each value a reference into the one place it is edited.
#
# mini-app-polis-ecosystem (prd and dev) is the vault: every value is
# edited there, once, and rotator-cog and rotate.py write only there. A
# consumer's project holds references to it
# (${mini-app-polis-ecosystem.prd.NAME}), under the names its code reads,
# and its syncs carry only those. A change in the vault re-syncs every
# config that references it. The one value kept outside it is Spotify's
# refresh token (spotify.tf).
#
# Terraform owns the projects and the syncs, never a secret: a
# doppler_secret resource keeps the value it resolves to in state, so the
# references are written by scripts/doppler_references.py from the
# `references` output instead (README.md, "Doppler layout").

locals {
  vault = "mini-app-polis-ecosystem"

  # Connections are made once, in the dashboard (Integrations); these are
  # their ids, which are not secrets.
  parameter_store_connection = "4b4a84c2-b695-4f88-8526-797cd5e06d66"

  environments = {
    dev = "Development"
    prd = "Production"
  }

  # The Lambda workers, from the root's outputs: each worker's project and
  # the vault name behind each name its code reads.
  workers = data.terraform_remote_state.infra.outputs.doppler_consumers

  # What a worker's dev config adds for local runs, where the function's
  # own environment (ENVIRONMENT, KAIANO_API_BASE_URL) is not there. Outside
  # production the API client reads KAIANO_API_BASE_URL_DEV instead.
  worker_dev_extras = {
    ENVIRONMENT             = "ENVIRONMENT"
    KAIANO_API_BASE_URL     = "KAIANO_API_BASE_URL"
    KAIANO_API_BASE_URL_DEV = "KAIANO_API_BASE_URL_DEV"
  }

  # What a worker's prd config adds for a local command against production
  # (`doppler run --config prd`): the function's own environment again. The
  # function never loads these from Parameter Store; it has them already.
  worker_prd_extras = {
    ENVIRONMENT         = "ENVIRONMENT"
    KAIANO_API_BASE_URL = "KAIANO_API_BASE_URL"
  }

  # Every project whose prd config syncs to Parameter Store, under
  # /mini-app-polis/<project>/prd/: the workers, and the root itself,
  # which reads the alert address its budget and alarms email (account.tf).
  parameter_store_consumers = merge(
    {
      for project, names in local.workers : project => {
        description = "${project}'s Lambda worker"
        prd         = merge(names, local.worker_prd_extras)
        dev         = merge(names, local.worker_dev_extras)
      }
    },
    {
      infra = {
        description = "infra's own reads"
        prd         = { CONTACT_TO_EMAIL = "CONTACT_TO_EMAIL" }
        dev         = {}
      }
    },
  )
}

data "terraform_remote_state" "infra" {
  backend = "s3"
  config = {
    bucket = "mini-app-polis-tfstate-400200465748"
    key    = "infra.tfstate"
    region = "us-east-1"
  }
}

# ── Consumers that read Parameter Store ──────────────────────────────────

moved {
  from = doppler_project.worker
  to   = doppler_project.consumer
}

moved {
  from = doppler_environment.worker
  to   = doppler_environment.consumer
}

moved {
  from = doppler_secrets_sync_aws_parameter_store.worker
  to   = doppler_secrets_sync_aws_parameter_store.consumer
}

resource "doppler_project" "consumer" {
  for_each = local.parameter_store_consumers

  name        = each.key
  description = "${each.value.description}: references into ${local.vault}, under the names its code reads. Layout in mini-app-polis/infra doppler/."
}

# A project made through the API has no environments, so no configs. Each
# environment's root config is named for its slug: prd syncs to AWS, dev is
# for local runs.
resource "doppler_environment" "consumer" {
  for_each = {
    for pair in setproduct(keys(doppler_project.consumer), keys(local.environments)) :
    "${pair[0]}/${pair[1]}" => { project = pair[0], slug = pair[1] }
  }

  project          = doppler_project.consumer[each.value.project].name
  slug             = each.value.slug
  name             = local.environments[each.value.slug]
  personal_configs = false
}

# prd to the project's own prefix, one parameter per secret, which only
# that consumer is granted. Doppler adds DOPPLER_CONFIG, DOPPLER_ENVIRONMENT
# and DOPPLER_PROJECT beside them; nothing reads those. Removing a consumer
# removes its parameters with it.
resource "doppler_secrets_sync_aws_parameter_store" "consumer" {
  for_each = doppler_project.consumer

  integration = local.parameter_store_connection
  project     = each.value.name
  config      = doppler_environment.consumer["${each.key}/prd"].slug

  region        = "us-east-1"
  path          = "/mini-app-polis/${each.value.name}/prd/"
  secure_string = true

  delete_behavior = "delete_from_target"
}

# ── References, written by scripts/doppler_references.py ─────────────────

locals {
  # Every config's references, one entry per config: the Parameter Store
  # consumers' prd and dev here, GitHub's in github.tf and Railway's in
  # railway.tf.
  reference_sets = concat(
    flatten([
      for project, consumer in local.parameter_store_consumers : [
        for config in keys(local.environments) : {
          project = project
          config  = config
          refs = {
            for name, source in consumer[config] :
            name => {
              ref        = contains(local.spotify_names, source) ? "$${${local.spotify}.prd.${source}}" : "$${${local.vault}.${config}.${source}}"
              visibility = null
            }
          }
        }
      ]
    ]),
    local.github_references,
    local.railway_references,
    local.local_dev_references,
    local.owner_session_references,
  )
}

output "references" {
  description = "Per project and config: each secret name → the reference it holds, and its visibility when set. scripts/doppler_references.py writes these."
  value = {
    for project in distinct([for set in local.reference_sets : set.project]) : project => {
      for set in local.reference_sets : set.config => set.refs if set.project == project
    }
  }
}
