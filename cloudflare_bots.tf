# Bot settings on the two zones that serve APIs.
#
# Bot Fight Mode challenges traffic from datacenter networks with a
# JavaScript page ("Just a moment..."), and on the Free plan no rule can
# exempt a caller from it. Every machine caller of these APIs comes from a
# datacenter — the AWS Lambda cogs, GitHub Actions (contract suites, smoke
# tests), GitHub's webhooks — so it stays off on these zones. Scanner traffic
# is handled by the path rules and rate limits in cloudflare_rules.tf
# instead. The static-site zones keep whatever the dashboard set.

locals {
  cloudflare_api_zones = toset(["deejaytools.com", "kaianolevine.com"])
}

resource "cloudflare_bot_management" "api_zones" {
  for_each = local.cloudflare_api_zones

  zone_id            = cloudflare_zone.this[each.key].id
  fight_mode         = false
  ai_bots_protection = "block"
}

import {
  for_each = local.cloudflare_api_zones
  to       = cloudflare_bot_management.api_zones[each.key]
  id       = local.cloudflare_zones[each.key]
}
