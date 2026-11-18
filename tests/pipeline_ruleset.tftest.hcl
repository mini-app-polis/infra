# modules/pipeline-ruleset: which repositories pipeline.yaml's on_pipeline
# puts under the organisation ruleset, and the tag its required workflow is
# read from. Planned against a mocked provider, so it reads nothing from
# GitHub:
#
#   terraform init && terraform test

mock_provider "github" {}

variables {
  pipeline_repository_id = 123
  excluded_repositories  = ["private-repo"]
  bypass_app_ids         = [456]
}

run "no_repository_on_the_pipeline_has_no_ruleset" {
  command = plan

  module {
    source = "./modules/pipeline-ruleset"
  }

  variables {
    pipeline_settings = "current_major: 3\non_pipeline: []\n"
  }

  assert {
    condition     = length(github_organization_ruleset.this) == 0
    error_message = "An empty on_pipeline declares no ruleset."
  }
}

run "missing_on_pipeline_has_no_ruleset" {
  command = plan

  module {
    source = "./modules/pipeline-ruleset"
  }

  variables {
    pipeline_settings = "current_major: 3\n"
  }

  assert {
    condition     = length(github_organization_ruleset.this) == 0
    error_message = "A missing on_pipeline declares no ruleset."
  }
}

run "listed_repositories_are_held_with_the_current_majors_workflow" {
  command = plan

  module {
    source = "./modules/pipeline-ruleset"
  }

  variables {
    pipeline_settings = "current_major: 4\non_pipeline:\n  - watcher-cog\n  - db-ops\n"
  }

  assert {
    condition     = output.repositories == tolist(["watcher-cog", "db-ops"])
    error_message = "The ruleset holds exactly the repositories on_pipeline lists: ${jsonencode(output.repositories)}"
  }

  assert {
    condition     = github_organization_ruleset.this[0].conditions[0].repository_name[0].exclude == tolist(["private-repo"])
    error_message = "The excluded repositories are never held."
  }

  assert {
    condition     = github_organization_ruleset.this[0].conditions[0].ref_name[0].include == tolist(["~DEFAULT_BRANCH"])
    error_message = "The ruleset holds the default branch only; dev takes direct pushes."
  }

  assert {
    condition     = one(github_organization_ruleset.this[0].rules[0].required_workflows[0].required_workflow).ref == "refs/tags/v4"
    error_message = "The required workflow is read at the current major's tag."
  }

  assert {
    condition     = one(github_organization_ruleset.this[0].rules[0].required_workflows[0].required_workflow).path == ".github/workflows/required.yml" && one(github_organization_ruleset.this[0].rules[0].required_workflows[0].required_workflow).repository_id == 123
    error_message = "The required workflow is .github's required.yml."
  }

  assert {
    condition     = github_organization_ruleset.this[0].rules[0].pull_request[0].required_approving_review_count == 0
    error_message = "A pull request is required, with no review."
  }

  assert {
    condition     = length(github_organization_ruleset.this[0].bypass_actors) == 1 && github_organization_ruleset.this[0].bypass_actors[0].actor_id == 456 && github_organization_ruleset.this[0].bypass_actors[0].actor_type == "Integration"
    error_message = "The bypass App is the ruleset's one bypass actor."
  }
}

run "all_holds_every_repository" {
  command = plan

  module {
    source = "./modules/pipeline-ruleset"
  }

  variables {
    pipeline_settings = "current_major: 4\non_pipeline: all\n"
  }

  assert {
    condition     = output.repositories == tolist(["~ALL"])
    error_message = "on_pipeline: all holds every repository."
  }
}
