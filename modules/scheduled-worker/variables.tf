variable "name" {
  description = "The cog's short name: \"watcher\", not \"watcher-cog\". Every resource is named from it."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.name)) && !endswith(var.name, "-cog")
    error_message = "name is the cog's short name in lowercase, without the -cog suffix."
  }
}

variable "github_repo" {
  description = "owner/repo whose workflows may assume the deploy role."
  type        = string
}

variable "github_oidc_provider_arn" {
  description = "The account's GitHub OIDC provider, from the root's account.tf."
  type        = string
}

variable "alert_email" {
  description = "Where the failing-ticks alarm goes. The subscription must be confirmed by hand before it delivers anything."
  type        = string
}

variable "api_base_url" {
  description = "api-kaianolevine-com."
  type        = string
}

# ── The function ─────────────────────────────────────────────────────────

variable "handler" {
  description = "Must match the cog's deploy job (lambda-deploy.yml `handler`)."
  type        = string
}

variable "architecture" {
  description = "Must match the deploy job's `architecture`."
  type        = string

  validation {
    condition     = contains(["arm64", "x86_64"], var.architecture)
    error_message = "architecture is arm64 or x86_64."
  }
}

variable "runtime" {
  description = "Must match the deploy job's `python-version`."
  type        = string
  default     = "python3.11"
}

variable "timeout_seconds" {
  description = "Above the slowest tick, and below the schedule interval so a slow tick cannot run into the next."
  type        = number
}

variable "memory_mb" {
  description = "Lambda scales CPU with memory."
  type        = number
}

variable "environment" {
  description = "Non-secret configuration beyond ENVIRONMENT, KAIANO_API_BASE_URL and the SSM_* names. Lands in state and in every plan."
  type        = map(string)
  default     = {}
}

# ── Schedule ─────────────────────────────────────────────────────────────

variable "schedule_interval_seconds" {
  description = "How often the function is invoked. A whole number of minutes; EventBridge's floor is one."
  type        = number
  default     = 60

  validation {
    condition     = var.schedule_interval_seconds >= 60 && var.schedule_interval_seconds % 60 == 0
    error_message = "schedule_interval_seconds is a whole number of minutes, at least 60."
  }
}

variable "enabled" {
  description = "Whether the schedule fires. Off until cutover: the function can be deployed and invoked by hand while the service it replaces still runs."
  type        = bool
  default     = true
}

variable "error_alarm_window" {
  description = "Ticks the failing alarm looks back over."
  type        = number
  default     = 5
}

variable "error_alarm_threshold" {
  description = "Failed ticks within the window that put the alarm into ALARM. Above one, so a single transient error does not page."
  type        = number
  default     = 3

  validation {
    condition     = var.error_alarm_threshold >= 1 && var.error_alarm_threshold <= var.error_alarm_window
    error_message = "error_alarm_threshold is between 1 and error_alarm_window."
  }
}

# ── Secrets, by name ─────────────────────────────────────────────────────

variable "ssm_prefix" {
  description = "Where Doppler syncs the ecosystem's prd config."
  type        = string
  default     = "/mini-app-polis/prd/"
}

variable "ssm_parameters" {
  description = "Environment variable name → parameter name under ssm_prefix. Loaded at cold start; a missing one fails it."
  type        = map(string)
}

variable "ssm_optional_parameters" {
  description = "As ssm_parameters, for settings the code has its own default for."
  type        = map(string)
  default     = {}
}

variable "log_retention_days" {
  description = "CloudWatch Logs retains forever by default."
  type        = number
  default     = 14
}
