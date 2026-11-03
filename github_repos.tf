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
# repository on the free plan), nor a ruleset. It and .github have no dev
# branch, and .github has no protect-main ruleset. infra's second
# ruleset, "main" (pull requests and the plan check required), is held by
# hand, not here.

locals {
  github_repos = {
    ".github"                = { dev_branch = false, protect_main = false }
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
    "wcs-wiki"               = { visibility = "private", dev_branch = false, protect_main = false }
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
  protect_main                 = lookup(each.value, "protect_main", true)
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

# The protect-main rulesets each repository already had, by id (GET
# /repos/mini-app-polis/<repo>/rulesets, 2026-11-03), so the import adopts
# them rather than adding a second one.
locals {
  protect_main_ruleset_ids = {
    "api-deejaytools"        = 25272798
    "api-kaianolevine-com"   = 25272786
    "common-python-utils"    = 25272804
    "db-ops"                 = 25272796
    "deejay-cog"             = 25272802
    "deejaytools-com"        = 25272787
    "ecosystem-standards"    = 25272794
    "evaluator-cog"          = 25272797
    "identity"               = 25272803
    "infra"                  = 25272805
    "kwalla-dance"           = 25272793
    "rotator-cog"            = 25911285
    "task-groomer-cog"       = 25911286
    "task-manager-cog"       = 25503875
    "transcription-cog"      = 25272801
    "watcher-cog"            = 25272799
    "website-astro-software" = 25272789
    "website-astro-wcs"      = 25272790
    "website-astro-wcsmn"    = 25272792
    "wiki-curator-cog"       = 25272795
  }
}

import {
  for_each = local.protect_main_ruleset_ids
  to       = module.github_repo[each.key].github_repository_ruleset.protect_main[0]
  id       = "${each.key}:${each.value}"
}
