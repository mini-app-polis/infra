# The organisation ruleset that holds the default branch of every
# repository on the canonical pipeline: a change reaches it only through a
# pull request (no review: the organisation has one member), and only once
# the pipeline's required workflow has passed on it. required.yml runs from
# mini-app-polis/.github at the current major's tag, in the target
# repository, so the repository cannot remove or edit it.
#
# Which repositories, and which tag, come from the pipeline's own settings
# (pipeline.yaml's on_pipeline and current_major); nothing here restates
# them. With no repository on the pipeline there is no ruleset.
#
# GitHub runs ruleset workflows only on pull request and merge-queue
# events, so dev, which takes direct pushes and auto-merges, is not held:
# every change reaches the default branch through the promotion pull
# request. A release pushes its commit there as a bypass App; GitHub does
# not accept GitHub Actions itself as a bypass actor.

locals {
  settings = yamldecode(var.pipeline_settings)

  # on_pipeline is a list of repository names, "all", or missing.
  on_pipeline = try(local.settings.on_pipeline, null)
  repositories = (
    local.on_pipeline == null ? [] :
    local.on_pipeline == "all" ? ["~ALL"] :
    [for name in local.on_pipeline : tostring(name)]
  )
}

resource "github_organization_ruleset" "this" {
  count = length(local.repositories) > 0 ? 1 : 0

  name        = "pipeline-main"
  target      = "branch"
  enforcement = "active"

  conditions {
    ref_name {
      include = ["~DEFAULT_BRANCH"]
      exclude = []
    }
    repository_name {
      include = local.repositories
      exclude = var.excluded_repositories
    }
  }

  dynamic "bypass_actors" {
    for_each = var.bypass_app_ids
    content {
      actor_id    = bypass_actors.value
      actor_type  = "Integration"
      bypass_mode = "always"
    }
  }

  rules {
    pull_request {
      required_approving_review_count = 0
    }

    required_workflows {
      required_workflow {
        repository_id = var.pipeline_repository_id
        path          = ".github/workflows/required.yml"
        ref           = "refs/tags/v${local.settings.current_major}"
      }
    }
  }
}
