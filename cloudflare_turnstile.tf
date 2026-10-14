# The Turnstile widget the sites' contact and sign-up forms use. The secret
# key is not returned by the API and is not managed here; the sites read it
# from Doppler.

resource "cloudflare_turnstile_widget" "kaiano_api" {
  account_id      = var.cloudflare_account_id
  name            = "kaiano-api"
  mode            = "managed"
  region          = "world"
  bot_fight_mode  = false
  clearance_level = "no_clearance"
  ephemeral_id    = false
  offlabel        = false

  domains = [
    "kaiano.dev",
    "kaianolevine.com",
    "mnmusicmovement.com",
    "mnwcs.com",
    "wcsmn.com",
    "website-astro-wcs.pages.dev",
    "www.kaianolevine.com",
    "www.mnmusicmovement.com",
    "www.mnwcs.com",
    "www.wcsmn.com",
  ]
}
