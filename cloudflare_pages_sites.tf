# The three Pages sites whose build variables Terraform owns.
#
# Doppler is where every value is edited. It syncs to this repository's
# Actions secrets, and the workflow passes each one in as TF_VAR_<name>, so a
# value keeps one name from Doppler to the build. Each variable below is
# named for what the site's build reads and is plain text: all of them end
# up in the browser bundle, so none is a secret.
#
# Production and preview differ only in the API they point at (and the
# Clerk instance behind deejaytools' dev API).

locals {
  cloudflare_pages_sites = {
    "deejaytools-com" = {
      repo_name           = "deejaytools-com"
      repo_id             = "1195655361"
      build_command       = "pnpm install && pnpm build"
      compatibility_date  = "2026-03-30"
      compatibility_flags = []
      production_env = {
        DEEJAYTOOLS_API                   = var.DEEJAYTOOLS_API
        DEEJAYTOOLS_CLERK_PUBLISHABLE_KEY = var.DEEJAYTOOLS_CLERK_PUBLISHABLE_KEY
        SENTRY_DSN_DEEJAYTOOLS            = var.SENTRY_DSN_DEEJAYTOOLS
      }
      preview_env = {
        DEEJAYTOOLS_API_DEV               = var.DEEJAYTOOLS_API_DEV
        DEEJAYTOOLS_CLERK_PUBLISHABLE_KEY = var.DEEJAYTOOLS_CLERK_PUBLISHABLE_KEY_DEV
        SENTRY_DSN_DEEJAYTOOLS            = var.SENTRY_DSN_DEEJAYTOOLS
      }
    }
    "website-astro-wcs" = {
      repo_name           = "website-astro-wcs"
      repo_id             = "1192108883"
      build_command       = "npm run build"
      compatibility_date  = "2024-09-23"
      compatibility_flags = ["nodejs_compat"]
      production_env = {
        KAIANO_API_BASE_URL       = var.KAIANO_API_BASE_URL
        PUBLIC_TURNSTILE_SITE_KEY = var.PUBLIC_TURNSTILE_SITE_KEY
      }
      preview_env = {
        KAIANO_API_BASE_URL       = var.KAIANO_API_BASE_URL_DEV
        PUBLIC_TURNSTILE_SITE_KEY = var.PUBLIC_TURNSTILE_SITE_KEY
      }
    }
    "website-astro-wcsmn" = {
      repo_name           = "website-astro-wcsmn"
      repo_id             = "1272498043"
      build_command       = "npm run build"
      compatibility_date  = "2026-06-17"
      compatibility_flags = []
      production_env = {
        GOOGLE_CALENDAR_PUBLIC_API_KEY = var.GOOGLE_CALENDAR_PUBLIC_API_KEY
      }
      preview_env = {
        GOOGLE_CALENDAR_PUBLIC_API_KEY = var.GOOGLE_CALENDAR_PUBLIC_API_KEY
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
