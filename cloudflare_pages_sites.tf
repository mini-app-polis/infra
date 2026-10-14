# The three Pages sites whose build variables Terraform owns. Unlike the
# projects in cloudflare_pages.tf, their deployment settings are managed
# here in full: every variable is plain text (each ends up in the browser
# bundle anyway), so nothing has to stay outside Terraform. Changing one is
# a pull request; the next build of the site picks it up.

locals {
  cloudflare_pages_sites = {
    "deejaytools-com" = {
      repo_name           = "deejaytools-com"
      repo_id             = "1195655361"
      build_command       = "pnpm install && pnpm build"
      compatibility_date  = "2026-03-30"
      compatibility_flags = []
      production_env = {
        VITE_API_URL               = "https://api.deejaytools.com"
        VITE_CLERK_PUBLISHABLE_KEY = var.deejaytools_clerk_publishable_key
        VITE_SENTRY_DSN            = var.deejaytools_sentry_dsn
      }
      preview_env = {
        VITE_API_URL               = "https://api-dev.deejaytools.com"
        VITE_CLERK_PUBLISHABLE_KEY = var.deejaytools_clerk_publishable_key_preview
        VITE_SENTRY_DSN            = var.deejaytools_sentry_dsn
      }
    }
    "website-astro-wcs" = {
      repo_name           = "website-astro-wcs"
      repo_id             = "1192108883"
      build_command       = "npm run build"
      compatibility_date  = "2024-09-23"
      compatibility_flags = ["nodejs_compat"]
      production_env = {
        KAIANO_API_BASE_URL       = "https://api.kaianolevine.com"
        PUBLIC_TURNSTILE_SITE_KEY = cloudflare_turnstile_widget.kaiano_api.sitekey
      }
      preview_env = {
        KAIANO_API_BASE_URL       = "https://dev-api.kaianolevine.com"
        PUBLIC_TURNSTILE_SITE_KEY = cloudflare_turnstile_widget.kaiano_api.sitekey
      }
    }
    "website-astro-wcsmn" = {
      repo_name           = "website-astro-wcsmn"
      repo_id             = "1272498043"
      build_command       = "npm run build"
      compatibility_date  = "2026-06-17"
      compatibility_flags = []
      production_env = {
        PUBLIC_API_URL                 = "https://api.kaianolevine.com"
        PUBLIC_GOOGLE_CALENDAR_API_KEY = var.wcsmn_google_calendar_api_key
      }
      preview_env = {
        PUBLIC_API_URL                 = "https://dev-api.kaianolevine.com"
        PUBLIC_GOOGLE_CALENDAR_API_KEY = var.wcsmn_google_calendar_api_key
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

import {
  for_each = local.cloudflare_pages_sites
  to       = cloudflare_pages_project.site[each.key]
  id       = "${var.cloudflare_account_id}/${each.key}"
}
