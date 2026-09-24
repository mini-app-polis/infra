variable "name" {
  description = <<-DESC
    The cog's short name: "deejay", not "deejay-cog". Every resource is named
    from it, and it is load-bearing — the queue is `<name>-jobs`, and
    api-kaianolevine-com derives the same queue name from the cog, and the
    API's producer policy covers `*-jobs`.
  DESC
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.name)) && !endswith(var.name, "-cog")
    error_message = "name is the cog's short name in lowercase, without the -cog suffix."
  }
}

variable "github_repo" {
  description = "owner/repo whose workflows may assume the deploy role. The cog's own repository: it owns the code, this owns everything else."
  type        = string
}

variable "github_oidc_provider_arn" {
  description = "The account's GitHub OIDC provider. There is one per account; it lives in the root's account.tf."
  type        = string
}

variable "alert_email" {
  description = "Where the dead-letter alarm goes. The subscription must be confirmed by hand before it delivers anything."
  type        = string
}

variable "api_base_url" {
  description = "api-kaianolevine-com, which every worker calls back to."
  type        = string
}

# ── The function ─────────────────────────────────────────────────────────

variable "handler" {
  description = "Must match the cog's deploy job (lambda-deploy.yml `handler`) and the package layout it uploads. A mismatch fails at the first invocation, not at deploy."
  type        = string
}

variable "architecture" {
  description = "arm64 unless a compiled dependency has no aarch64 wheel. Must match the deploy job's `architecture`; the deploy refuses a mismatch."
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
  description = "Above the slowest observed job, with headroom. The queue's visibility timeout is derived from it, so the two cannot drift. 900 is Lambda's ceiling."
  type        = number

  validation {
    condition     = var.timeout_seconds >= 1 && var.timeout_seconds <= 900
    error_message = "Lambda's timeout is 1–900 seconds."
  }
}

variable "memory_mb" {
  description = "Lambda scales CPU with memory. Tune against the billed-duration metric."
  type        = number
}

variable "environment" {
  description = <<-DESC
    Non-secret configuration, beyond what every worker gets (ENVIRONMENT,
    KAIANO_API_BASE_URL and the SSM_* names). Nothing secret goes here —
    this lands in state and in every plan. Secrets go in ssm_parameters.
  DESC
  type        = map(string)
  default     = {}
}

# ── Secrets, by name ─────────────────────────────────────────────────────

variable "ssm_prefix" {
  description = "Where Doppler syncs the ecosystem's prd config."
  type        = string
  default     = "/mini-app-polis/prd/"
}

variable "ssm_parameters" {
  description = <<-DESC
    Environment variable name → parameter name under ssm_prefix. The worker
    loads these at cold start (mini_app_polis.ssm_secrets) and its role may
    read these and nothing else. A missing one fails the cold start.
  DESC
  type        = map(string)
}

variable "ssm_optional_parameters" {
  description = "As ssm_parameters, for settings the code has its own default for. Missing means left unset, never \"\"."
  type        = map(string)
  default     = {}
}

# ── Queue and concurrency ────────────────────────────────────────────────

variable "max_receive_count" {
  description = "Deliveries before a message is dead-lettered. Raise it when reserved_concurrency is 1: a throttled attempt still counts."
  type        = number
  default     = 3
}

variable "reserved_concurrency" {
  description = <<-DESC
    A reservation on the function. 1 serialises runs — the setting for a
    cog that sweeps a shared resource, where two runs would race. -1 means
    unreserved; the ceiling is then max_concurrency. State exactly one of
    the two (PIPE-018).
  DESC
  type        = number
  default     = -1
}

variable "max_concurrency" {
  description = <<-DESC
    The event source mapping's ceiling on concurrent invocations. At least
    2 (AWS's floor), and AWS refuses one above the function's reservation —
    so a cog that needs 1 sets reserved_concurrency = 1 and leaves this
    null. Exactly one of the two is set (PIPE-018).
  DESC
  type        = number
  default     = null

  validation {
    condition     = var.max_concurrency == null || var.max_concurrency >= 2
    error_message = "SQS event source mappings require maximum_concurrency >= 2. For 1, set reserved_concurrency = 1 instead."
  }

  validation {
    condition     = (var.max_concurrency != null) != (var.reserved_concurrency > 0)
    error_message = "State the concurrency ceiling exactly once (PIPE-018): reserved_concurrency > 0, or max_concurrency — not both, not neither."
  }
}

variable "log_retention_days" {
  description = "CloudWatch Logs retains forever by default; this group is declared so it does not."
  type        = number
  default     = 30
}
