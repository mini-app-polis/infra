# One-time adoption of what was built in the Cloudflare dashboard. Once
# main has applied these, delete this file in the next pull request, as was
# done for the AWS imports.

import {
  for_each = local.cloudflare_zones
  to       = cloudflare_zone.this[each.key]
  id       = each.value
}
