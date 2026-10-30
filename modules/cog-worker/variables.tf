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

variable "github_oidc_subject" {
  description = <<-DESC
    The repository part of the OIDC subject its workflows present, when it
    is not repo:<github_repo>. GitHub gives repositories created since
    October 2026 immutable subjects, repo:<owner>@<owner id>/<repo>@<repo
    id>, and they cannot opt out. Unset, the name form is trusted.
  DESC
  type        = string
  default     = null

  validation {
    condition     = var.github_oidc_subject == null || can(regex("^repo:[^:]+$", var.github_oidc_subject))
    error_message = "github_oidc_subject is repo:<...> with no ref part; the ref is pinned by the module."
  }
}

variable "github_oidc_provider_arn" {
  description = "The account's GitHub OIDC provider. There is one per account; it lives in the root's account.tf."
  type        = string
}

variable "alert_email" {
  description = "Where the module's alarms go. The subscription must be confirmed by hand before it delivers anything."
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

variable "duration_alarm_ratio" {
  description = "The share of timeout_seconds the longest job may take before the duration alarm fires: low enough that the timeout can be raised while slow jobs still finish."
  type        = number
  default     = 0.8

  validation {
    condition     = var.duration_alarm_ratio > 0 && var.duration_alarm_ratio < 1
    error_message = "duration_alarm_ratio is a share of the timeout, between 0 and 1 exclusive."
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

variable "ssm_parameters" {
  description = <<-DESC
    Environment variable name → the name of its value in the vault
    (mini-app-polis-secrets or mini-app-polis-settings, prd). The worker's own Doppler config holds a
    reference to that value under the environment variable's name, synced to
    /mini-app-polis/<repository>/prd/. The worker loads these at cold start
    (mini_app_polis.ssm_secrets) and its role may read these and nothing
    else. A missing one fails the cold start.
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
  description = "Deliveries before a message is dead-lettered. On a standard queue with reserved_concurrency = 1 a throttled attempt still counts, so raise it there; a FIFO queue is not throttled, so 3 is enough."
  type        = number
  default     = 3
}

variable "fifo" {
  description = <<-DESC
    Make the queue and its dead-letter queue FIFO (names end .fifo). For a
    serial cog: the producer sends every job in one message group, so the
    trigger is handed one message at a time and nothing waiting is ever
    throttled into spending a delivery. A standard queue with
    reserved_concurrency = 1 dead-letters good jobs under a burst larger
    than max_receive_count. The cost is head-of-line blocking: a failing
    job holds the queue until it succeeds or is dead-lettered. The producer
    (api-kaianolevine-com job_queue.FIFO_COGS) must agree.
  DESC
  type        = bool
  default     = false
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

variable "own_queue_url_variable" {
  description = <<-DESC
    For a cog that queues jobs for itself: the environment variable that
    carries its own jobs queue's URL. Set, the worker's role may also
    sqs:SendMessage to that queue and nothing else. Null (the default)
    leaves the worker a consumer only.
  DESC
  type        = string
  default     = null
}

variable "send_queues" {
  description = <<-DESC
    Other cogs' queues this worker hands jobs to, by the environment
    variable that carries each queue's URL. The worker's role may
    sqs:SendMessage to exactly these queues, and its environment holds
    their URLs. Its own queue goes through own_queue_url_variable instead.
  DESC
  type = map(object({
    url = string
    arn = string
  }))
  default = {}
}

variable "layers" {
  description = "Lambda layer version ARNs the function runs with: native binaries its package cannot carry. None by default."
  type        = list(string)
  default     = []
}

variable "schedules" {
  description = <<-DESC
    Jobs the cog runs on a clock, by name. Each puts its body on the cog's
    own queue on its schedule expression ("rate(1 hour)", "cron(...)"), so
    a scheduled job waits its turn behind the queue's other jobs rather
    than running beside them. On a FIFO queue it is sent in the message
    group the API uses, the cog's name. The body is the cog's to define.
  DESC
  type = map(object({
    expression = string
    body       = string
  }))
  default = {}
}

variable "log_retention_days" {
  description = "CloudWatch Logs retains forever by default; this group is declared so it does not."
  type        = number
  default     = 30
}
