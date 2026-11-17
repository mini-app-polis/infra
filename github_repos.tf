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
# branch. .github's second ruleset, "main", is below. infra's second
# ruleset, "main" (pull requests and the plan check required), is held by
# hand, not here.

locals {
  github_repos = {
    ".github"                = { dev_branch = false }
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
}

# Each repository here and its protect-main ruleset were adopted with import
# blocks (2026-11-03), removed once applied.

# .github is the pipeline's source and has no dev, so a change reaches main
# only by a pull request whose security checks pass (.github README,
# "Changing the pipeline"). No review is required: the organisation has one
# member, who cannot approve their own pull request; CODEOWNERS names the
# owner of the workflow and action paths without gating on it. The release
# commit and the moved major tag are pushed by GitHub Actions with the job's
# token, which bypasses the rule. The checks are the gating jobs of .github's
# own ci.yml, each from GitHub Actions.
resource "github_repository_ruleset" "shared_workflows_main" {
  name        = "main"
  repository  = module.github_repo[".github"].name
  target      = "branch"
  enforcement = "active"

  conditions {
    ref_name {
      include = ["~DEFAULT_BRANCH"]
      exclude = []
    }
  }

  bypass_actors {
    # GitHub Actions.
    actor_id    = 15368
    actor_type  = "Integration"
    bypass_mode = "always"
  }

  rules {
    pull_request {
      required_approving_review_count   = 0
      dismiss_stale_reviews_on_push     = false
      require_code_owner_review         = false
      require_last_push_approval        = false
      required_review_thread_resolution = false
    }

    required_status_checks {
      strict_required_status_checks_policy = false

      required_check {
        context        = "security / secret scan"
        integration_id = 15368
      }
      required_check {
        context        = "security / dependency audit (python)"
        integration_id = 15368
      }
      required_check {
        context        = "test / secret scan"
        integration_id = 15368
      }
      required_check {
        context        = "test / dependency audit (node)"
        integration_id = 15368
      }
    }
  }
}

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
