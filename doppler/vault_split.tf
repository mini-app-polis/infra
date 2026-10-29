# The vault, in two projects: mini-app-polis-secrets holds what rotator-cog
# rotates, mini-app-polis-settings everything else.
#
# Every reference this root builds points at one of the two, by name:
# vault_home says which. A name in local.vault_secret_names is a secret;
# every other name is a setting. That list is generated, never edited:
# scripts/doppler_split.py generate writes it to vault_secret_names.tf.json
# from rotator-cog's secrets/inventory.yaml, by the same rule its sort and
# copy use (README.md, "Doppler layout").
#
# As everywhere in this root, Terraform owns the projects, never a value.

locals {
  vault_secrets  = "mini-app-polis-secrets"
  vault_settings = "mini-app-polis-settings"

  split_vaults = {
    (local.vault_secrets)  = "The fleet's secrets: what rotator-cog rotates, and the names a rotation writes."
    (local.vault_settings) = "The fleet's settings: every value that is not a rotated secret."
  }

  # The project of each secret name. Look a name up with
  # lookup(local.vault_home, NAME, local.vault_settings): a name not here is
  # a setting.
  vault_home = { for name in local.vault_secret_names : name => local.vault_secrets }
}

resource "doppler_project" "split_vault" {
  for_each = local.split_vaults

  name        = each.key
  description = "${each.value} Layout in mini-app-polis/infra doppler/."
}

# A project made through the API has no environments, so no configs: prd
# and dev.
resource "doppler_environment" "split_vault" {
  for_each = {
    for pair in setproduct(keys(local.split_vaults), keys(local.environments)) :
    "${pair[0]}/${pair[1]}" => { project = pair[0], slug = pair[1] }
  }

  project          = doppler_project.split_vault[each.value.project].name
  slug             = each.value.slug
  name             = local.environments[each.value.slug]
  personal_configs = false
}
