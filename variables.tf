variable "region" {
  description = "Everything in this account lives in US East, next to the Railway fleet the workers call back to."
  type        = string
  default     = "us-east-1"
}

variable "doppler_workplace_id" {
  description = "Doppler workplace ID, the external ID on the sync role's trust policy. Not a secret: it only works together with Doppler's own credentials."
  type        = string
  default     = "20209dff73a41e59b6c6"
}

variable "kaiano_api_base_url" {
  description = "api-kaianolevine-com, which every worker calls back to."
  type        = string
  default     = "https://api.kaianolevine.com"
}

variable "budget_limit_usd" {
  description = "Monthly budget. Set low on purpose — this should never fire."
  type        = number
  default     = 10
}

variable "cloudflare_account_id" {
  description = "The Cloudflare account every zone, Pages project and Worker lives in. Not a secret: it appears in every dashboard URL and does nothing without a token."
  type        = string
  default     = "0314578fe75f14199c748d0065583f93"
}

# Pages build values (cloudflare_pages_sites.tf), named as in Doppler. Public
# by design — each is baked into a site's browser bundle — but edited in
# Doppler and passed in by the workflow as TF_VAR_<name>.

variable "DEEJAYTOOLS_API" {
  description = "deejaytools API base URL, for production builds."
  type        = string
}

variable "DEEJAYTOOLS_API_DEV" {
  description = "deejaytools dev API base URL, for preview builds."
  type        = string
}

variable "DEEJAYTOOLS_CLERK_PUBLISHABLE_KEY" {
  description = "deejaytools production Clerk publishable key (pk_live_…)."
  type        = string
}

variable "DEEJAYTOOLS_CLERK_PUBLISHABLE_KEY_DEV" {
  description = "deejaytools dev Clerk instance's publishable key (pk_test_…), for preview builds."
  type        = string
}

variable "SENTRY_DSN_DEEJAYTOOLS" {
  description = "deejaytools browser Sentry DSN."
  type        = string
}

variable "KAIANO_API_BASE_URL" {
  description = "api-kaianolevine-com base URL, for production builds."
  type        = string
}

variable "KAIANO_API_BASE_URL_DEV" {
  description = "api-kaianolevine-com dev base URL, for preview builds."
  type        = string
}

variable "PUBLIC_TURNSTILE_SITE_KEY" {
  description = "Turnstile site key for the kaiano-api widget."
  type        = string
}

variable "GOOGLE_CALENDAR_PUBLIC_API_KEY" {
  description = "wcsmn Google Calendar API key; referrer-restricted in Google Cloud."
  type        = string
}
