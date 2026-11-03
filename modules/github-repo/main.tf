# One repository in the fleet's shape: public, main as default branch with
# a dev branch beside it, secret scanning and push protection on, the
# fleet's merge options (set on create, not held: see the lifecycle block),
# Actions enabled with all actions allowed, and a workflow token that can
# write and open pull requests.
#
# Only what is declared here is held. Description, homepage, topics,
# rulesets and Actions variables are not (Actions variables arrive through
# doppler/github.tf).

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
    # not held afterwards.
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
