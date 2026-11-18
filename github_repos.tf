# Every repository in mini-app-polis that is not a cog, in the shape
# modules/github-repo declares. A cog's repository is created and held by
# its module block in cogs.tf. The list was read from the GitHub API
# (GET /orgs/mini-app-polis/repos) when these were first imported,
# 2026-11-03; a repository created since is added here or, for a cog,
# comes with its module block.
#
# Each entry is the module's defaults (the fleet's shape) plus the ways
# that repository differs from it. A read-only default workflow token is a
# deliberate difference, not drift: those repositories' workflows ask for
# write where they need it, and narrowing a token is never a regression. wcs-wiki is private, so it
# has no secret scanning or push protection (not available on a private
# repository on the free plan), nor a ruleset. It and .github have no dev
# branch. infra's second
# ruleset, "main" (pull requests and the plan check required), is held by
# hand, not here.

locals {
  # The promote GitHub App (mini-app-polis-promote), by its numeric App ID.
  promote_app_id = 5111724

  github_repos = {
    # The pipeline's own repository: changes land on dev like the rest of
    # the fleet, and main takes them by pull request with its CI passing;
    # the release pushes its version commit as the promote App, the one
    # bypass.
    ".github" = {
      main_requires_pull_request = true
      main_required_checks = [
        "security / secret scan",
        "security / dependency audit (python)",
        "security / static analysis",
        "security / sbom",
        # self-test.yml's gate: workflow static analysis, the release
        # tooling's audit and every profile's fixture.
        "test / gate",
      ]
      main_bypass_app_ids = [local.promote_app_id]
    }
    "api-deejaytools"        = {}
    "api-kaianolevine-com"   = { default_workflow_permissions = "read" }
    "common-python-utils"    = {}
    "db-ops"                 = {}
    "deejaytools-com"        = {}
    "ecosystem-standards"    = {}
    "identity"               = {}
    "infra"                  = {}
    "kwalla-dance"           = {}
    "wcs-wiki"               = { visibility = "private", dev_branch = false, protect_main = false }
    "website-astro-software" = { default_workflow_permissions = "read" }
    "website-astro-wcs"      = { default_workflow_permissions = "read" }
    "website-astro-wcsmn"    = {}
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
  main_requires_pull_request   = lookup(each.value, "main_requires_pull_request", false)
  main_required_checks         = lookup(each.value, "main_required_checks", [])
  main_bypass_app_ids          = lookup(each.value, "main_bypass_app_ids", [])
}

# Each repository here and its protect-main ruleset were adopted with import
# blocks (2026-11-03), removed once applied.

# A cog's repository is held by its own module block (cogs.tf); these
# were declared here first.

moved {
  from = module.github_repo["deejay-cog"]
  to   = module.deejay.module.repository[0]
}

moved {
  from = module.github_repo["evaluator-cog"]
  to   = module.evaluator.module.repository[0]
}

moved {
  from = module.github_repo["rotator-cog"]
  to   = module.rotator.module.repository[0]
}

# task-groomer-cog renamed task-refiner-cog: the repository moved to the
# refiner's block, and the new name renamed it in place.
moved {
  from = module.task_groomer.module.repository[0]
  to   = module.task_refiner.module.repository[0]
}

moved {
  from = module.github_repo["task-manager-cog"]
  to   = module.task_manager.module.repository[0]
}

moved {
  from = module.github_repo["transcription-cog"]
  to   = module.transcription.module.repository[0]
}

moved {
  from = module.github_repo["watcher-cog"]
  to   = module.watcher.module.repository[0]
}

moved {
  from = module.github_repo["wiki-curator-cog"]
  to   = module.wiki_curator.module.repository[0]
}
