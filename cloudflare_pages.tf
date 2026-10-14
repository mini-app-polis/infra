# Cloudflare Pages: the static sites and their custom domains.
#
# Terraform owns each project's build settings and Git connection, and every
# custom domain. Deployment settings (environment variables, compatibility
# date) are not managed here: Doppler syncs the variables, most of them are
# secrets the API never returns, and the provider cannot import a project
# that has any. The five projects with secret variables are therefore not
# here yet — website-astro-wcs, deejaytools-com, website-astro-wcsmn,
# website-swingtacular and website-astro-swingtacular — and join once their
# build secrets are narrowed to what each site actually reads. Their custom
# domains are managed below regardless.
#
# Deployments themselves come from the Git integration; nothing here
# triggers one.

locals {
  cloudflare_pages_projects = {
    "bameo-wcs" = {
      owner           = "dance-geek-productions"
      owner_id        = "281515657"
      repo_name       = "bameo-wcs"
      repo_id         = "1261618080"
      build_command   = "npm run build"
      destination_dir = "dist"
    }
    "capital-swing-convention" = {
      owner           = "dance-geek-productions"
      owner_id        = "281515657"
      repo_name       = "capital-swing-convention"
      repo_id         = "1261617700"
      build_command   = "npm run build"
      destination_dir = "dist"
    }
    "kwalla-dance" = {
      owner           = "mini-app-polis"
      owner_id        = "270520182"
      repo_name       = "kwalla-dance"
      repo_id         = "1338786445"
      build_command   = "npm run build"
      destination_dir = "dist"
    }
    "wcsmn-com" = {
      owner           = "kaianolevine"
      owner_id        = "202033240"
      repo_name       = "wcsmn.com"
      repo_id         = "1143831533"
      build_command   = "git fetch --force --tags --prune || true && git fetch --unshallow --tags 2>/dev/null || true && SITE_VERSION=\"$(git describe --tags --abbrev=0 2>/dev/null || git describe --tags --always)\" npm run build:11ty"
      destination_dir = "dist"
    }
    "website-astro-software" = {
      owner           = "mini-app-polis"
      owner_id        = "270520182"
      repo_name       = "website-astro-software"
      repo_id         = "1186385635"
      build_command   = "npm run build"
      destination_dir = "dist"
    }
  }

  # Custom domain → the Pages project serving it, for every project in the
  # account, managed or not yet.
  cloudflare_pages_domains = {
    "deejaytools.com"               = "deejaytools-com"
    "dev.deejaytools.com"           = "deejaytools-com"
    "www.deejaytools.com"           = "deejaytools-com"
    "kwalla.dance"                  = "kwalla-dance"
    "dev.software.kaianolevine.com" = "website-astro-software"
    "software.kaianolevine.com"     = "website-astro-software"
    "dev.wcs.kaianolevine.com"      = "website-astro-wcs"
    "wcs.kaianolevine.com"          = "website-astro-wcs"
    "mnwcs.com"                     = "website-astro-wcsmn"
    "wcsmn.com"                     = "website-astro-wcsmn"
    "www.mnwcs.com"                 = "website-astro-wcsmn"
    "www.wcsmn.com"                 = "website-astro-wcsmn"
    "dev.swingtacular.art"          = "website-swingtacular"
    "swingtacular.art"              = "website-swingtacular"
    "www.swingtacular.art"          = "website-swingtacular"
  }
}

resource "cloudflare_pages_project" "this" {
  for_each = local.cloudflare_pages_projects

  account_id        = var.cloudflare_account_id
  name              = each.key
  production_branch = "main"

  build_config = {
    build_command   = each.value.build_command
    destination_dir = each.value.destination_dir
    root_dir        = ""
  }

  source = {
    type = "github"
    config = {
      owner                          = each.value.owner
      owner_id                       = each.value.owner_id
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
    # Environment variables and compatibility settings belong to Doppler and
    # the dashboard (see the header).
    ignore_changes = [deployment_configs]
  }
}

resource "cloudflare_pages_domain" "this" {
  for_each = local.cloudflare_pages_domains

  account_id   = var.cloudflare_account_id
  project_name = each.value
  name         = each.key
}
