# The vault, split in two: mini-app-polis-secrets holds what rotator-cog
# rotates, mini-app-polis-settings everything else.
#
# Both sit beside mini-app-polis-ecosystem (main.tf's local.vault), which
# stays the vault every reference points at until the consumers are moved.
# scripts/doppler_split.py sorts the vault's names between the two, copies
# the values over, and proves the move (README.md, "Splitting the vault").
# As everywhere in this root, Terraform owns the projects, never a value.

locals {
  split_vaults = {
    "mini-app-polis-secrets"  = "The fleet's secrets: what rotator-cog rotates, and the names a rotation writes."
    "mini-app-polis-settings" = "The fleet's settings: every value that is not a rotated secret."
  }
}

resource "doppler_project" "split_vault" {
  for_each = local.split_vaults

  name        = each.key
  description = "${each.value} Layout in mini-app-polis/infra doppler/."
}

# A project made through the API has no environments, so no configs: prd
# and dev, as in the vault.
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
