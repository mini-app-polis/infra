# One repository in the fleet's shape: public, main as default branch with
# a dev branch beside it, secret scanning and push protection on, the
# fleet's merge options (set on create, not held: see the lifecycle block),
# Actions enabled with all actions allowed, and a workflow token that can
# write and open pull requests.
#
# Only what is declared here is held. Description, homepage, topics, any
# ruleset other than protect-main, and Actions variables are not (Actions
# variables arrive through doppler/github.tf).

resource "github_repository" "this" {
  name       = var.name
  visibility = var.visibility

  has_issues      = true
  has_projects    = true
  has_wiki        = var.has_wiki
  has_discussions = false

  allow_merge_commit          = true
  allow_squash_merge          = true
  allow_rebase_merge          = true
  allow_auto_merge            = false
  allow_update_branch         = false
  delete_branch_on_merge      = false
  merge_commit_title          = "MERGE_MESSAGE"
  merge_commit_message        = "PR_TITLE"
  squash_merge_commit_title   = "COMMIT_OR_PR_TITLE"
  squash_merge_commit_message = "COMMIT_MESSAGES"
  web_commit_signoff_required = false

  # Secret scanning and push protection are free on public repositories
  # only, so a private one carries no block.
  dynamic "security_and_analysis" {
    for_each = var.visibility == "public" ? [1] : []
    content {
      secret_scanning {
        status = "enabled"
      }
      secret_scanning_push_protection {
        status = "enabled"
      }
    }
  }

  # A destroy would delete the repository and its history; archive instead,
  # and refuse a plan that tries.
  archive_on_destroy = true

  lifecycle {
    prevent_destroy = true

    # GitHub returns a repository's merge options only to a caller with push
    # access, and the infra-read App that plans has none, so it reads them
    # as false or unset. They are set when a repository is created here and
    # not held afterwards. The infra-write App that applies does have push
    # access (Contents write), so an update sends their real values back;
    # it must keep it, or an apply would turn every merge method off.
    ignore_changes = [
      allow_merge_commit,
      allow_squash_merge,
      allow_rebase_merge,
      merge_commit_title,
      merge_commit_message,
      squash_merge_commit_title,
      squash_merge_commit_message,
    ]
  }
}

resource "github_branch" "dev" {
  count = var.dev_branch ? 1 : 0

  repository = github_repository.this.name
  branch     = "dev"

  # The branch exists and moves with every merge; where it started from is
  # not something to hold.
  lifecycle {
    ignore_changes = [source_branch, source_sha]
  }
}

resource "github_branch_default" "this" {
  repository = github_repository.this.name
  branch     = "main"
}

resource "github_actions_repository_permissions" "this" {
  repository      = github_repository.this.name
  enabled         = true
  allowed_actions = "all"
}

resource "github_workflow_repository_permissions" "this" {
  repository                       = github_repository.this.name
  default_workflow_permissions     = var.default_workflow_permissions
  can_approve_pull_request_reviews = true
}

# The fleet's protect-main ruleset: the default branch cannot be deleted
# or force-pushed. A per-repository ruleset, so it holds every repository,
# on the canonical pipeline or not (the pipeline's own organisation
# ruleset is modules/pipeline-ruleset).
#
# A repository can also require that changes arrive by pull request with
# named checks passing. A ruleset applies to its bypass actors only as far
# as the bypass goes, so the Apps named in main_bypass_app_ids (a release
# pushing its version commit) skip the pull-request and check rules; GitHub
# does not accept GitHub Actions itself as a bypass actor.
resource "github_repository_ruleset" "protect_main" {
  count = var.protect_main ? 1 : 0

  name        = "protect-main"
  repository  = github_repository.this.name
  target      = "branch"
  enforcement = "active"

  conditions {
    ref_name {
      include = ["~DEFAULT_BRANCH"]
      exclude = []
    }
  }

  dynamic "bypass_actors" {
    for_each = var.main_bypass_app_ids
    content {
      actor_id    = bypass_actors.value
      actor_type  = "Integration"
      bypass_mode = "always"
    }
  }

  rules {
    deletion         = true
    non_fast_forward = true

    dynamic "pull_request" {
      for_each = var.main_requires_pull_request ? [1] : []
      content {
        required_approving_review_count = 0
      }
    }

    dynamic "required_status_checks" {
      for_each = length(var.main_required_checks) > 0 ? [1] : []
      content {
        strict_required_status_checks_policy = false
        dynamic "required_check" {
          for_each = var.main_required_checks
          content {
            context = required_check.value
          }
        }
      }
    }
  }

  # GitHub returns a ruleset's bypass actors only to a caller that can edit
  # it, and the infra-read App that plans cannot, so it reads them as none
  # and every plan would add them back. They are set when the ruleset is
  # created here and not held afterwards: a change to main_bypass_app_ids
  # on an existing ruleset needs a -replace of it to take effect.
  lifecycle {
    ignore_changes = [bypass_actors]
  }
}
