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

  zone_id               = cloudflare_zone.this[each.key].id
  fight_mode            = false
  is_robots_txt_managed = true

  # The AI-crawler settings belong to AI Crawl Control in the dashboard. The
  # API won't take ai_bots_protection through this resource (a "block" comes
  # back as "disabled"), so Terraform leaves these fields alone.
  lifecycle {
    ignore_changes = [
      ai_bots_protection,
      ai_bots_migration_opt_out,
      ai_training,
      ai_user,
      aisearch,
      content_bots_protection,
      crawler_protection,
    ]
  }
}

import {
  for_each = local.cloudflare_api_zones
  to       = cloudflare_bot_management.api_zones[each.key]
  id       = local.cloudflare_zones[each.key]
}
