# The organisation's rulesets (organisation rulesets need GitHub Team, which
# the organisation is on). pipeline-main holds the default branch of every
# repository on the canonical pipeline (modules/pipeline-ruleset), read
# from the pipeline's settings on mini-app-polis/.github's main branch: a
# repository is held from the first apply after it is added to
# `on_pipeline` there. Repositories declared here without the protect-main
# ruleset (wcs-wiki: private, no CI) are never held, even under "all".

data "github_repository" "pipeline" {
  name = ".github"
}

data "github_repository_file" "pipeline_settings" {
  repository = ".github"
  branch     = "main"
  file       = "pipeline.yaml"
}

module "pipeline_ruleset" {
  source = "./modules/pipeline-ruleset"

  pipeline_settings      = data.github_repository_file.pipeline_settings.content
  pipeline_repository_id = data.github_repository.pipeline.repo_id
  excluded_repositories = [
    for name, repo in local.github_repos : name
    if !lookup(repo, "protect_main", true)
  ]
  bypass_app_ids = [local.promote_app_id]
}
