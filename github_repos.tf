# Every repository in mini-app-polis, in the shape modules/github-repo
# declares. The list was read from the GitHub API (GET /orgs/mini-app-polis/repos)
# when these were first imported, 2026-11-03; a repository created since
# is added here.
#
# Each entry is the module's defaults (the fleet's shape) plus the ways
# that repository differs today. The differences were imported as they
# are, so the first apply changed nothing; bringing one into line is its
# own change, and removes its override here. wcs-wiki is private, so it
# has no secret scanning or push protection (not available on a private
# repository on the free plan), and it has no dev branch.

locals {
  github_repos = {
    ".github"                = {}
    "api-deejaytools"        = { has_wiki = true }
    "api-kaianolevine-com"   = { has_wiki = true, default_workflow_permissions = "read" }
    "common-python-utils"    = {}
    "db-ops"                 = { has_wiki = true }
    "deejay-cog"             = { has_wiki = true, default_workflow_permissions = "read" }
    "deejaytools-com"        = {}
    "ecosystem-standards"    = { has_wiki = true }
    "evaluator-cog"          = { has_wiki = true, default_workflow_permissions = "read" }
    "identity"               = {}
    "infra"                  = { has_wiki = true }
    "kwalla-dance"           = {}
    "rotator-cog"            = { has_wiki = true }
    "task-groomer-cog"       = {}
    "task-manager-cog"       = {}
    "transcription-cog"      = {}
    "watcher-cog"            = { has_wiki = true, default_workflow_permissions = "read" }
    "wcs-wiki"               = { visibility = "private", dev_branch = false }
    "website-astro-software" = { has_wiki = true, default_workflow_permissions = "read" }
    "website-astro-wcs"      = { default_workflow_permissions = "read" }
    "website-astro-wcsmn"    = {}
    "wiki-curator-cog"       = {}
  }
}

module "github_repo" {
  source   = "./modules/github-repo"
  for_each = local.github_repos

  name                         = each.key
  visibility                   = lookup(each.value, "visibility", "public")
  dev_branch                   = lookup(each.value, "dev_branch", true)
  has_wiki                     = lookup(each.value, "has_wiki", false)
  default_workflow_permissions = lookup(each.value, "default_workflow_permissions", "write")
}

# Adopted, not created: each repository already existed.
import {
  for_each = local.github_repos
  to       = module.github_repo[each.key].github_repository.this
  id       = each.key
}

import {
  for_each = { for name, repo in local.github_repos : name => repo if lookup(repo, "dev_branch", true) }
  to       = module.github_repo[each.key].github_branch.dev[0]
  id       = "${each.key}:dev"
}

import {
  for_each = local.github_repos
  to       = module.github_repo[each.key].github_branch_default.this
  id       = each.key
}

import {
  for_each = local.github_repos
  to       = module.github_repo[each.key].github_actions_repository_permissions.this
  id       = each.key
}

import {
  for_each = local.github_repos
  to       = module.github_repo[each.key].github_workflow_repository_permissions.this
  id       = each.key
}
