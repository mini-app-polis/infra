variable "name" {
  description = "The repository's name in mini-app-polis."
  type        = string
}

variable "visibility" {
  description = "public, or private for a repository that must not be public."
  type        = string
  default     = "public"

  validation {
    condition     = contains(["public", "private"], var.visibility)
    error_message = "visibility is public or private."
  }
}

variable "dev_branch" {
  description = "Whether the repository has a dev branch (the fleet's integration branch)."
  type        = bool
  default     = true
}

variable "has_wiki" {
  description = "Whether the wiki is on. The fleet's shape is off."
  type        = bool
  default     = false
}

variable "default_workflow_permissions" {
  description = "The GITHUB_TOKEN's default permissions in workflows: write (the fleet's shape) or read."
  type        = string
  default     = "write"

  validation {
    condition     = contains(["read", "write"], var.default_workflow_permissions)
    error_message = "default_workflow_permissions is read or write."
  }
}
