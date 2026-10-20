# The Pages sites whose build variables Terraform owns.
#
# Doppler is where every value is edited; Terraform reads them straight from
# the mini-app-polis-ecosystem / prd config with a read-only service token
# (DOPPLER_TOKEN_PAGES), so there is no sync to keep alive and a value keeps
# one name from Doppler to the build. Each variable below is named for what
# the site's build reads and is plain text: all of them end up in the
# browser bundle, so none is a secret.
#
# Where production and preview differ, it is only in the API they point at
# and the Clerk instance behind it: deejaytools and wcs each have a
# development Clerk instance, and their preview builds carry its pk_test_ key
# (the *_DEV values, which reference the dev config from prd).
#
# PUBLIC_SITE_URL is a literal rather than a Doppler value: it is a site's
# canonical domain, not a secret, and the same in every environment.

data "doppler_secrets" "pages" {
  project = "mini-app-polis-ecosystem"
  config  = "prd"
}

locals {
  # Only the named values are taken from the config, and only they are
  # unmarked: they are public, and for_each cannot iterate over sensitive
  # values. Everything else in the config stays sensitive and unused.
  doppler = { for n in local.cloudflare_pages_doppler_names : n => nonsensitive(trimspace(lookup(data.doppler_secrets.pages.map, n, ""))) }

  # Every Doppler value a site build below needs. A missing or empty one
  # fails the plan rather than blanking a live site.
  cloudflare_pages_doppler_names = [
    "DEEJAYTOOLS_API",
    "DEEJAYTOOLS_API_DEV",
    "DEEJAYTOOLS_CLERK_PUBLISHABLE_KEY",
    "DEEJAYTOOLS_CLERK_PUBLISHABLE_KEY_DEV",
    "SENTRY_DSN_DEEJAYTOOLS",
    "KAIANO_API_BASE_URL",
    "KAIANO_API_BASE_URL_DEV",
    "PUBLIC_CLERK_PUBLISHABLE_KEY",
    "PUBLIC_CLERK_PUBLISHABLE_KEY_DEV",
    "PUBLIC_TURNSTILE_SITE_KEY",
    "GOOGLE_CALENDAR_PUBLIC_API_KEY",
    "PUBLIC_API_URL",
    "PUBLIC_CALENDAR_ICS_URL",
  ]

  cloudflare_pages_sites = {
    "deejaytools-com" = {
      repo_name           = "deejaytools-com"
      repo_id             = "1195655361"
      build_command       = "pnpm install && pnpm build"
      compatibility_date  = "2026-03-30"
      compatibility_flags = []
      production_env = {
        DEEJAYTOOLS_API                   = local.doppler["DEEJAYTOOLS_API"]
        DEEJAYTOOLS_CLERK_PUBLISHABLE_KEY = local.doppler["DEEJAYTOOLS_CLERK_PUBLISHABLE_KEY"]
        SENTRY_DSN_DEEJAYTOOLS            = local.doppler["SENTRY_DSN_DEEJAYTOOLS"]
      }
      preview_env = {
        DEEJAYTOOLS_API_DEV               = local.doppler["DEEJAYTOOLS_API_DEV"]
        DEEJAYTOOLS_CLERK_PUBLISHABLE_KEY = local.doppler["DEEJAYTOOLS_CLERK_PUBLISHABLE_KEY_DEV"]
        SENTRY_DSN_DEEJAYTOOLS            = local.doppler["SENTRY_DSN_DEEJAYTOOLS"]
      }
    }
    "website-astro-wcs" = {
      repo_name           = "website-astro-wcs"
      repo_id             = "1192108883"
      build_command       = "npm run build"
      compatibility_date  = "2024-09-23"
      compatibility_flags = ["nodejs_compat"]
      production_env = {
        KAIANO_API_BASE_URL          = local.doppler["KAIANO_API_BASE_URL"]
        PUBLIC_CLERK_PUBLISHABLE_KEY = local.doppler["PUBLIC_CLERK_PUBLISHABLE_KEY"]
        PUBLIC_TURNSTILE_SITE_KEY    = local.doppler["PUBLIC_TURNSTILE_SITE_KEY"]
      }
      preview_env = {
        KAIANO_API_BASE_URL          = local.doppler["KAIANO_API_BASE_URL_DEV"]
        PUBLIC_CLERK_PUBLISHABLE_KEY = local.doppler["PUBLIC_CLERK_PUBLISHABLE_KEY_DEV"]
        PUBLIC_TURNSTILE_SITE_KEY    = local.doppler["PUBLIC_TURNSTILE_SITE_KEY"]
      }
    }
    "website-astro-wcsmn" = {
      repo_name           = "website-astro-wcsmn"
      repo_id             = "1272498043"
      build_command       = "npm run build"
      compatibility_date  = "2026-06-17"
      compatibility_flags = []
      production_env = {
        GOOGLE_CALENDAR_PUBLIC_API_KEY = local.doppler["GOOGLE_CALENDAR_PUBLIC_API_KEY"]
      }
      preview_env = {
        GOOGLE_CALENDAR_PUBLIC_API_KEY = local.doppler["GOOGLE_CALENDAR_PUBLIC_API_KEY"]
      }
    }
    "website-astro-software" = {
      repo_name           = "website-astro-software"
      repo_id             = "1186385635"
      build_command       = "npm run build"
      compatibility_date  = "2024-01-01"
      compatibility_flags = []
      production_env = {
        PUBLIC_API_URL            = local.doppler["PUBLIC_API_URL"]
        PUBLIC_SITE_URL           = "https://software.kaianolevine.com"
        PUBLIC_TURNSTILE_SITE_KEY = local.doppler["PUBLIC_TURNSTILE_SITE_KEY"]
      }
      preview_env = {
        PUBLIC_API_URL            = local.doppler["KAIANO_API_BASE_URL_DEV"]
        PUBLIC_SITE_URL           = "https://software.kaianolevine.com"
        PUBLIC_TURNSTILE_SITE_KEY = local.doppler["PUBLIC_TURNSTILE_SITE_KEY"]
      }
    }
    "kwalla-dance" = {
      repo_name           = "kwalla-dance"
      repo_id             = "1338786445"
      build_command       = "npm run build"
      compatibility_date  = "2026-01-01"
      compatibility_flags = []
      # Pages project variables reach the site's Functions as well as its
      # build, so functions/api/calendar.ts reads the feed address from here.
      production_env = {
        PUBLIC_CALENDAR_ICS_URL = local.doppler["PUBLIC_CALENDAR_ICS_URL"]
        PUBLIC_SITE_URL         = "https://kwalla.dance"
      }
      preview_env = {
        PUBLIC_CALENDAR_ICS_URL = local.doppler["PUBLIC_CALENDAR_ICS_URL"]
        PUBLIC_SITE_URL         = "https://kwalla.dance"
      }
    }
  }
}

resource "cloudflare_pages_project" "site" {
  for_each = local.cloudflare_pages_sites

  account_id        = var.cloudflare_account_id
  name              = each.key
  production_branch = "main"

  build_config = {
    build_command   = each.value.build_command
    destination_dir = "dist"
    root_dir        = ""
  }

  source = {
    type = "github"
    config = {
      owner                          = "mini-app-polis"
      owner_id                       = "270520182"
      repo_name                      = each.value.repo_name
      repo_id                        = each.value.repo_id
      production_branch              = "main"
      pr_comments_enabled            = true
      production_deployments_enabled = true
      preview_deployment_setting     = "all"
      preview_branch_includes        = ["*"]
      path_includes                  = ["*"]
    }
  }

  lifecycle {
    precondition {
      condition     = alltrue([for n in local.cloudflare_pages_doppler_names : local.doppler[n] != ""])
      error_message = "A Pages build value is missing or empty in Doppler (mini-app-polis-ecosystem / prd): ${join(", ", [for n in local.cloudflare_pages_doppler_names : n if local.doppler[n] == ""])}."
    }
  }

  deployment_configs = {
    production = {
      compatibility_date  = each.value.compatibility_date
      compatibility_flags = each.value.compatibility_flags
      fail_open           = true
      env_vars            = { for k, v in each.value.production_env : k => { type = "plain_text", value = v } }
    }
    preview = {
      compatibility_date  = each.value.compatibility_date
      compatibility_flags = each.value.compatibility_flags
      fail_open           = true
      env_vars            = { for k, v in each.value.preview_env : k => { type = "plain_text", value = v } }
    }
  }
}

# Back from cloudflare_pages_project.this, where they briefly sat with
# their variables left to the dashboard.
moved {
  from = cloudflare_pages_project.this["deejaytools-com"]
  to   = cloudflare_pages_project.site["deejaytools-com"]
}

moved {
  from = cloudflare_pages_project.this["website-astro-wcs"]
  to   = cloudflare_pages_project.site["website-astro-wcs"]
}

moved {
  from = cloudflare_pages_project.this["website-astro-wcsmn"]
  to   = cloudflare_pages_project.site["website-astro-wcsmn"]
}

# From cloudflare_pages_project.this, where software's variables were left
# to the dashboard and kwalla's to its wrangler.toml.
moved {
  from = cloudflare_pages_project.this["website-astro-software"]
  to   = cloudflare_pages_project.site["website-astro-software"]
}

moved {
  from = cloudflare_pages_project.this["kwalla-dance"]
  to   = cloudflare_pages_project.site["kwalla-dance"]
}
