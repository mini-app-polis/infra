# Cloudflare: the edge in front of every site and API.
#
# Thirteen zones, all on the Free plan, were created in the dashboard and
# adopted here by import. Terraform owns them from
# here on: a change made in the dashboard is drift, and the next apply puts
# it back.
#
# Two tokens, mirroring the AWS plan and apply roles (ci.tf):
#
#   CLOUDFLARE_API_TOKEN_READ  repository secret, plan job. Read-only on
#                              everything below, so a pull request's plan
#                              can change nothing.
#   CLOUDFLARE_API_TOKEN       `production` environment secret, apply job
#                              only. Edit on the same scopes.
#
# Both are minted by hand in the dashboard and stored in Doppler; neither
# passes through Terraform or lands in state. Scopes are listed in the
# README.
#
# Registration, renewal and transfer stay in the dashboard: the registrar
# is not something Terraform should be able to give away.
#
# Out of scope by decision: the swingesota Workers (swingesota-api,
# swingesota-api-ro) and their Hyperdrive config (swingesota-hd). They share
# this account but are not part of this platform.

locals {
  # Zone name → zone ID. The IDs are what the imports adopt; the names are
  # what everything else in this configuration refers to.
  cloudflare_zones = {
    "dancegeekproductions.art" = "a8352b0a8083ed08661ba44a12b2223b"
    "deejaytools.com"          = "210ee7814003903a62dcb7e8d365de43"
    "emberlabshq.app"          = "b96d22aab9f9bd297e93d09da2c2ac88"
    "kaiano.dev"               = "502af7622cedc866287d4e174bee02a2"
    "kaiano.fyi"               = "973a1acc2064db9b190ef54c03df2f23"
    "kaianolevine.com"         = "1f0c5adaaf7879e2ac4d6c169a485895"
    "kwalla.dance"             = "820408fee4063914e2bdc15f6a33412b"
    "miniapppolis.com"         = "d85c4d1b3fd4ca3df0554b1d7a938b5e"
    "mnmusicmovement.com"      = "16eda36fbb6fc03e454eafc99c1c2bcc"
    "mnwcs.com"                = "f02b1de4ea672bfb6844cd4885fb6fb5"
    "swingtacular.art"         = "e47355e5817fa876c4e9c2aab6037bcf"
    "syncright.dev"            = "531ff3c01cdf67b5d9b01dc19c8d98e0"
    "wcsmn.com"                = "bc661db2a663cb9cf78a07706ffd7ab2"
  }
}

resource "cloudflare_zone" "this" {
  for_each = local.cloudflare_zones

  account = {
    id = var.cloudflare_account_id
  }
  name = each.key
  type = "full"

  lifecycle {
    # Deleting a zone takes every record, rule and certificate with it, and
    # a registrar domain's zone cannot simply be recreated. allow-destroy is
    # not enough for this one: removing it means editing this line first.
    prevent_destroy = true
  }
}
