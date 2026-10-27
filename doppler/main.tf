# Doppler's layout: a project per consumer, holding only what that consumer
# reads, each value a reference into the one place it is edited.
#
# mini-app-polis-ecosystem (prd and dev) is the vault: every value is
# edited there, once, and rotator-cog and rotate.py write only there. A
# consumer's project holds references to it (${mini-app-polis-ecosystem.prd.NAME}),
# under the names its code reads, and its syncs carry only those. A change
# in the vault re-syncs every config that references it.
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

  # The Lambda workers, from the root's outputs: each worker's project and
  # the vault name behind each name its code reads.
  workers = data.terraform_remote_state.infra.outputs.doppler_consumers

  environments = {
    dev = "Development"
    prd = "Production"
  }

  # What a worker's dev config adds for local runs, where the function's
  # own environment (ENVIRONMENT, KAIANO_API_BASE_URL) is not there.
  worker_dev_extras = {
    ENVIRONMENT         = "ENVIRONMENT"
    KAIANO_API_BASE_URL = "KAIANO_API_BASE_URL"
  }
}

data "terraform_remote_state" "infra" {
  backend = "s3"
  config = {
    bucket = "mini-app-polis-tfstate-400200465748"
    key    = "infra.tfstate"
    region = "us-east-1"
  }
}

# ── Lambda workers ───────────────────────────────────────────────────────

resource "doppler_project" "worker" {
  for_each = local.workers

  name        = each.key
  description = "${each.key}'s Lambda worker: references into ${local.vault}, under the names its code reads. Layout in mini-app-polis/infra doppler/."
}

# A project made through the API has no environments, so no configs. Each
# environment's root config is named for its slug: prd syncs to AWS, dev is
# for local runs.
resource "doppler_environment" "worker" {
  for_each = {
    for pair in setproduct(keys(doppler_project.worker), keys(local.environments)) :
    "${pair[0]}/${pair[1]}" => { project = pair[0], slug = pair[1] }
  }

  project          = doppler_project.worker[each.value.project].name
  slug             = each.value.slug
  name             = local.environments[each.value.slug]
  personal_configs = false
}

# prd to the worker's own prefix, one parameter per secret, which the
# root's own_doppler_config points the function at and grants it alone.
# Removing a worker removes its parameters with it.
resource "doppler_secrets_sync_aws_parameter_store" "worker" {
  for_each = doppler_project.worker

  integration = local.parameter_store_connection
  project     = each.value.name
  config      = doppler_environment.worker["${each.key}/prd"].slug

  region        = "us-east-1"
  path          = "/mini-app-polis/${each.value.name}/prd/"
  secure_string = true

  delete_behavior = "delete_from_target"
}

# ── References, written by scripts/doppler_references.py ─────────────────

output "references" {
  description = "Per project and config: each secret name → the reference it holds. scripts/doppler_references.py writes these."
  value = {
    for project, names in local.workers : project => {
      prd = { for name, source in names : name => "$${${local.vault}.prd.${source}}" }
      dev = { for name, source in merge(names, local.worker_dev_extras) : name => "$${${local.vault}.dev.${source}}" }
    }
  }
}
