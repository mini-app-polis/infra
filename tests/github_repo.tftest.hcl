# modules/github-repo: the fleet's shape by default, and a private
# repository without the public-only security settings. Planned against a
# mocked provider, so it reads nothing from GitHub:
#
#   terraform init && terraform test

mock_provider "github" {}

run "public_repo_has_the_fleet_shape" {
  command = plan

  module {
    source = "./modules/github-repo"
  }

  variables {
    name = "example-cog"
  }

  assert {
    condition     = github_repository.this.visibility == "public" && github_repository.this.has_wiki == false
    error_message = "A repository is public with its wiki off by default."
  }

  assert {
    condition     = length(github_repository.this.security_and_analysis) == 1
    error_message = "A public repository has secret scanning and push protection declared."
  }

  assert {
    condition     = length(github_branch.dev) == 1 && github_branch_default.this.branch == "main"
    error_message = "A repository has main as default branch and a dev branch."
  }

  assert {
    condition     = github_workflow_repository_permissions.this.default_workflow_permissions == "write" && github_workflow_repository_permissions.this.can_approve_pull_request_reviews
    error_message = "Workflows can write and open pull requests by default."
  }
}

run "private_repo_has_no_public_only_settings" {
  command = plan

  module {
    source = "./modules/github-repo"
  }

  variables {
    name       = "example-private"
    visibility = "private"
    dev_branch = false
  }

  assert {
    condition     = length(github_repository.this.security_and_analysis) == 0
    error_message = "A private repository declares no secret scanning (not available on the free plan)."
  }

  assert {
    condition     = length(github_branch.dev) == 0
    error_message = "dev_branch = false declares no dev branch."
  }
}
