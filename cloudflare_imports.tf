# One-time adoption of what was built in the Cloudflare dashboard. Once
# main has applied these, delete this file in the next pull request.

import {
  for_each = local.cloudflare_pages_projects
  to       = cloudflare_pages_project.this[each.key]
  id       = "${var.cloudflare_account_id}/${each.key}"
}

import {
  for_each = local.cloudflare_pages_domains
  to       = cloudflare_pages_domain.this[each.key]
  id       = "${var.cloudflare_account_id}/${each.value}/${each.key}"
}

import {
  to = cloudflare_turnstile_widget.kaiano_api
  id = "0314578fe75f14199c748d0065583f93/0x4AAAAAACXUS6RYhJCvPzZg"
}
