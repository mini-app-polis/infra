variable "pipeline_settings" {
  description = "The text of pipeline.yaml, the canonical pipeline's settings in mini-app-polis/.github: its current_major and on_pipeline are read."
  type        = string
}

variable "pipeline_repository_id" {
  description = "The numeric ID of mini-app-polis/.github, which holds the required workflow."
  type        = number
}

variable "excluded_repositories" {
  description = "Repositories never held, even when on_pipeline is \"all\": those without CI to run the required workflow."
  type        = list(string)
  default     = []
}

variable "bypass_app_ids" {
  description = "Numeric IDs of GitHub Apps that may push to a held default branch past the ruleset, such as the App a release pushes with."
  type        = list(number)
  default     = []
}
